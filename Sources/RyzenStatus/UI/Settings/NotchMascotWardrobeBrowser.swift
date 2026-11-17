// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import SwiftUI

// MARK: - Families, spots and order

/// The families the wardrobe keeps its things in: what the levels bring,
/// then every batch the shop has sold, in the order they came to it.
enum NotchMascotWardrobeFamily: Int, CaseIterable, Identifiable {
    case levels, wonderBoy, curiosities, dance, toys, party, oddities, workshop, fair, lab, mayhem

    var id: Int { rawValue }

    var items: [NotchMascotAccessory] {
        switch self {
        case .levels: return Self.levelItems
        case .wonderBoy: return NotchMascotAccessory.rpgItems
        case .curiosities: return NotchMascotAccessory.shopItems
        case .dance: return NotchMascotAccessory.danceItems
        case .toys: return NotchMascotAccessory.toyItems
        case .party: return NotchMascotAccessory.partyItems
        case .oddities: return NotchMascotAccessory.oddityItems
        case .workshop: return NotchMascotAccessory.craftItems
        case .fair: return NotchMascotAccessory.fairItems
        case .lab: return NotchMascotAccessory.labItems
        case .mayhem: return NotchMascotAccessory.mayhemItems
        }
    }

    /// The seventeen a level opens, without the empty choice.
    static let levelItems: [NotchMascotAccessory] = NotchMascotAccessory.wardrobe.filter { !$0.isPurchasable && $0 != .none }

    private static let byItem: [NotchMascotAccessory: NotchMascotWardrobeFamily] = {
        var map: [NotchMascotAccessory: NotchMascotWardrobeFamily] = [:]
        for family in allCases { for item in family.items { map[item] = family } }
        return map
    }()

    static func of(_ item: NotchMascotAccessory) -> NotchMascotWardrobeFamily? { byItem[item] }

    /// The two newest batches, marked so they are found among the rest.
    var isNew: Bool { self == .lab || self == .mayhem }

    var symbol: String {
        switch self {
        case .levels: return "star.fill"
        case .wonderBoy: return "shield.fill"
        case .curiosities: return "sparkles"
        case .dance: return "music.note"
        case .toys: return "gift.fill"
        case .party: return "party.popper.fill"
        case .oddities: return "questionmark.diamond.fill"
        case .workshop: return "hammer.fill"
        case .fair: return "tent.fill"
        case .lab: return "flask.fill"
        case .mayhem: return "burst.fill"
        }
    }
}

/// Where a thing is worn, as the filter reads it. Headphones go on the
/// ears, which the filter counts with the head.
enum NotchMascotWardrobeSpot: Int, CaseIterable, Identifiable {
    case head, eyes, neck, hand, back, feet

    var id: Int { rawValue }

    static func of(_ item: NotchMascotAccessory) -> NotchMascotWardrobeSpot {
        switch item.placement {
        case .head, .ears: return .head
        case .eyes: return .eyes
        case .neck: return .neck
        case .hand: return .hand
        case .back: return .back
        case .feet: return .feet
        }
    }
}

/// How the wardrobe is laid out: by family, rarest first, by name, or cheapest first.
enum NotchMascotWardrobeSort: Int, CaseIterable, Identifiable {
    case family, rarity, name, price
    var id: Int { rawValue }
}

/// Whether the wardrobe shows everything, only what the figure may wear, or only what it may not yet.
enum NotchMascotWardrobeOwnership: Int, CaseIterable, Identifiable {
    case all, owned, notOwned
    var id: Int { rawValue }
}

/// What a thing does in a chain reaction, read from the chain's own rules:
/// what it throws to start one, and what it makes of each thing thrown at
/// it, with luck held at the middle so the answer is always the same.
struct NotchMascotChainFacts {
    struct Reaction: Hashable {
        let stimulus: NotchMascotStimulus
        let thrown: NotchMascotStimulus?
    }

    let emits: NotchMascotStimulus?
    let reactions: [Reaction]

    var isEmpty: Bool { emits == nil && reactions.isEmpty }

    init(_ item: NotchMascotAccessory) {
        guard item != .none else {
            emits = nil
            reactions = []
            return
        }
        // What the thing itself throws, without the figure's own breath or
        // spark that `NotchMascotChain.emission(item:style:)` falls back to.
        emits = NotchMascotChainReactions.itemEmission(item)?.stimulus
        reactions = NotchMascotStimulus.allCases.compactMap { stimulus in
            NotchMascotChainReactions.itemReaction(item, to: stimulus, random: { 0.5 })
                .map { Reaction(stimulus: stimulus, thrown: $0.emits) }
        }
    }
}

// MARK: - The browser

/// The wardrobe on the companion's Settings page: two hundred things and
/// more, found by name, by family, by where they are worn and by whether
/// they are owned, sorted four ways, and kept in families that open and
/// close from their whole header so the page is never one wall of tiles.
/// A click puts on what the figure may wear and opens, under its family,
/// what the thing is, what it costs and what it does in a chain; what is
/// not owned yet can be bought there when the shop has it on show.
struct NotchMascotWardrobeBrowser: View {
    /// One figure the wardrobe can dress.
    struct Wearer {
        let style: NotchMascotStyle
        let level: Int
        let name: String
        /// The look its previews are drawn on.
        let look: NotchMascotLook
        /// What it wears, as stored: a raw value, or empty for the friend's own pick.
        let pick: Binding<String>
        /// The friend may leave the choice to itself.
        let offersOwnPick: Bool
        /// After a pick, so the figure out on the desktop changes too.
        let picked: () -> Void
    }

    let companion: Wearer
    let friend: Wearer?
    let language: AppLanguage
    /// Bumped by every purchase, so what is owned is read again.
    let purchases: Int
    /// The page's scroll view, to bring a family into view as it opens.
    var scroll: ScrollViewProxy?

    @State private var dressingFriend = false
    @State private var query = ""
    @State private var family: NotchMascotWardrobeFamily?
    @State private var spot: NotchMascotWardrobeSpot?
    @State private var ownership = NotchMascotWardrobeOwnership.all
    @State private var sort = NotchMascotWardrobeSort.family
    /// Shelves opened by hand while nothing is filtered.
    @State private var opened: Set<String> = []
    /// Shelves closed by hand while a filter is on, when every shelf starts open.
    @State private var closedWhileFiltering: Set<String> = []
    @State private var seeded = false
    /// The thing whose card is open under its shelf.
    @State private var inspected: NotchMascotAccessory?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var text: NotchMascotWardrobeStrings { FeatureStrings.notchMascotWardrobe(language) }
    private var life: NotchMascotLifeStrings { FeatureStrings.notchMascotLife(language) }
    private var shopText: NotchMascotShopStrings { FeatureStrings.notchMascotShop(language) }
    private var animation: Animation? { reduceMotion ? nil : .smooth(duration: 0.22) }

    /// Everything that can be picked, without the empty choice, which has a tile of its own.
    static let catalog: [NotchMascotAccessory] = NotchMascotAccessory.wardrobe.filter { $0 != .none }
    /// Things on a shelf when they are sorted by name.
    private static let nameShelf = 24

    private var wearer: Wearer { dressingFriend ? (friend ?? companion) : companion }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var filtering: Bool { !trimmedQuery.isEmpty || family != nil || spot != nil || ownership != .all }

    /// What the figure wears now; nil while the friend picks for itself.
    private var wornItem: NotchMascotAccessory? {
        let raw = wearer.pick.wrappedValue
        if wearer.offersOwnPick && raw.isEmpty { return nil }
        return NotchMascotAccessory(rawValue: raw) ?? NotchMascotAccessory.none
    }

    private func wearable(_ item: NotchMascotAccessory) -> Bool {
        item.isUnlocked(level: wearer.level, for: wearer.style)
    }

    private func name(_ item: NotchMascotAccessory) -> String { life.name(of: item) }

    static func tint(_ rarity: NotchMascotRarity) -> Color {
        switch rarity {
        case .common: return .gray
        case .uncommon: return .green
        case .rare: return .blue
        case .legendary: return .orange
        }
    }

    var body: some View {
        _ = purchases
        let unfamilied = passing(ignoringFamily: true)
        let shown = family.map { chosen in unfamilied.filter { NotchMascotWardrobeFamily.of($0) == chosen } } ?? unfamilied
        let shelves = self.shelves(from: shown)
        return VStack(alignment: .leading, spacing: 10) {
            if let friend {
                SettingsChoiceRow(symbol: "person.2", title: text.dressing, selection: $dressingFriend) {
                    Text(companion.name).tag(false)
                    Text(friend.name).tag(true)
                }
            }
            searchAndSort
            familyChips(unfamilied)
            spotAndOwnershipChips
            summary(shown: shown.count, shelves: shelves)
            pinnedTiles
            if shelves.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(text.nothingMatches).font(.callout).foregroundStyle(.secondary)
                    Button(text.clearFilters, action: clearFilters).controlSize(.small)
                }
                .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(shelves) { shelfView($0) }
                }
            }
        }
        .padding(.leading, settingsRowTextInset)
        .onAppear {
            guard !seeded else { return }
            seeded = true
            seed()
        }
        .onChange(of: sort) { _, _ in seed() }
        .onChange(of: dressingFriend) { _, _ in inspected = nil }
        .onChange(of: filtering) { _, now in if now { closedWhileFiltering = [] } }
    }

    // MARK: Filters

    /// Every thing that passes the search, the spot and the ownership; the
    /// family chips count from these, then the family chosen narrows them.
    private func passing(ignoringFamily: Bool) -> [NotchMascotAccessory] {
        let needle = trimmedQuery
        return Self.catalog.filter { item in
            if !ignoringFamily, let family, NotchMascotWardrobeFamily.of(item) != family { return false }
            if let spot, NotchMascotWardrobeSpot.of(item) != spot { return false }
            switch ownership {
            case .all: break
            case .owned: if !wearable(item) { return false }
            case .notOwned: if wearable(item) { return false }
            }
            if !needle.isEmpty, !name(item).localizedStandardContains(needle) { return false }
            return true
        }
    }

    private func clearFilters() {
        withAnimation(animation) {
            query = ""
            family = nil
            spot = nil
            ownership = .all
        }
    }

    private var searchAndSort: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(text.search, text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(text.clearFilters)
                        .accessibilityLabel(text.clearFilters)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .frame(maxWidth: 280)
            Spacer(minLength: 0)
            Picker(text.sortTitle, selection: $sort) {
                ForEach(NotchMascotWardrobeSort.allCases) { Text(text.sort($0)).tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private func familyChips(_ items: [NotchMascotAccessory]) -> some View {
        var counts: [NotchMascotWardrobeFamily: Int] = [:]
        for item in items { if let family = NotchMascotWardrobeFamily.of(item) { counts[family, default: 0] += 1 } }
        return NotchMascotWardrobeFlow(spacing: 6) {
            NotchMascotWardrobeChip(title: text.all, count: items.count, selected: family == nil) {
                withAnimation(animation) { family = nil }
            }
            ForEach(NotchMascotWardrobeFamily.allCases) { item in
                NotchMascotWardrobeChip(title: text.family(item), count: counts[item] ?? 0, selected: family == item,
                                        symbol: item.symbol, badge: item.isNew ? text.newBadge : nil) {
                    withAnimation(animation) { family = family == item ? nil : item }
                }
                .opacity((counts[item] ?? 0) == 0 && family != item ? 0.5 : 1)
            }
        }
    }

    private var spotAndOwnershipChips: some View {
        NotchMascotWardrobeFlow(spacing: 6) {
            ForEach(NotchMascotWardrobeSpot.allCases) { item in
                NotchMascotWardrobeChip(title: text.spot(item), selected: spot == item) {
                    withAnimation(animation) { spot = spot == item ? nil : item }
                }
            }
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 1, height: 16)
            NotchMascotWardrobeChip(title: text.owned, selected: ownership == .owned, symbol: "checkmark.circle") {
                withAnimation(animation) { ownership = ownership == .owned ? .all : .owned }
            }
            NotchMascotWardrobeChip(title: text.notOwned, selected: ownership == .notOwned, symbol: "lock") {
                withAnimation(animation) { ownership = ownership == .notOwned ? .all : .notOwned }
            }
        }
    }

    private func summary(shown: Int, shelves: [Shelf]) -> some View {
        let allOpen = !shelves.isEmpty && shelves.allSatisfy(isOpen)
        return HStack(spacing: 10) {
            Text(text.shown(shown, of: Self.catalog.count))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 8)
            if filtering {
                Button(text.clearFilters, action: clearFilters)
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            if !shelves.isEmpty {
                Button(allOpen ? text.collapseAll : text.expandAll) {
                    let ids = Set(shelves.map(\.id))
                    withAnimation(animation) {
                        if filtering {
                            closedWhileFiltering = allOpen ? closedWhileFiltering.union(ids) : closedWhileFiltering.subtracting(ids)
                        } else {
                            opened = allOpen ? opened.subtracting(ids) : opened.union(ids)
                        }
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }

    /// The empty choice, and the friend's own pick, always at hand above the shelves.
    private var pinnedTiles: some View {
        HStack(spacing: 8) {
            if wearer.offersOwnPick {
                let own = FeatureStrings.notchMascotDesktop(language).friendItemOwn
                NotchMascotWardrobeTile(accessory: .none, symbol: "wand.and.stars", worn: wornItem == nil, inspected: false,
                                        unlocked: true, rarity: nil, isNew: false, title: own) {
                    wearer.pick.wrappedValue = ""
                    wearer.picked()
                    withAnimation(animation) { inspected = nil }
                }
            }
            NotchMascotWardrobeTile(accessory: .none, worn: wornItem == NotchMascotAccessory.none, inspected: false,
                                    unlocked: true, rarity: nil, isNew: false, title: name(.none)) {
                wear(.none)
                withAnimation(animation) { inspected = nil }
            }
            Text(wornItem.map(name) ?? FeatureStrings.notchMascotDesktop(language).friendItemOwn)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: Shelves

    /// One group of tiles under a header that opens and closes it.
    private struct Shelf: Identifiable {
        let id: String
        let title: String
        var symbol: String?
        var tint: Color?
        var isNew = false
        let items: [NotchMascotAccessory]
    }

    private func shelves(from items: [NotchMascotAccessory]) -> [Shelf] {
        switch sort {
        case .family:
            return NotchMascotWardrobeFamily.allCases.compactMap { family in
                let own = items.filter { NotchMascotWardrobeFamily.of($0) == family }
                return own.isEmpty ? nil : Shelf(id: "family-\(family.rawValue)", title: text.family(family),
                                                 symbol: family.symbol, isNew: family.isNew, items: own)
            }
        case .rarity, .price:
            // The prices of one rarity never reach the next, so cheapest
            // first is the rarities in order, each by its own prices. What
            // a level brings is never sold and comes last either way.
            let sold = items.filter(\.isPurchasable)
            let tiers = sort == .rarity ? Array(NotchMascotRarity.allCases.reversed()) : NotchMascotRarity.allCases
            var result: [Shelf] = tiers.compactMap { rarity in
                var own = sold.filter { $0.rarity == rarity }
                if sort == .price { own.sort { ($0.price, name($0)) < ($1.price, name($1)) } }
                return own.isEmpty ? nil : Shelf(id: "rarity-\(rarity.rawValue)", title: shopText.rarity(rarity),
                                                 tint: Self.tint(rarity), items: own)
            }
            let levels = items.filter { !$0.isPurchasable }
            if !levels.isEmpty {
                result.append(Shelf(id: "levels", title: text.family(.levels),
                                    symbol: NotchMascotWardrobeFamily.levels.symbol, items: levels))
            }
            return result
        case .name:
            // Shelves of two dozen, headed by their first and last letters,
            // which reads the same in every script.
            let sorted = items.sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
            return stride(from: 0, to: sorted.count, by: Self.nameShelf).map { start in
                let slice = Array(sorted[start..<min(start + Self.nameShelf, sorted.count)])
                let first = initial(slice.first)
                let last = initial(slice.last)
                return Shelf(id: "name-\(start / Self.nameShelf)", title: first == last ? first : "\(first) – \(last)",
                             items: slice)
            }
        }
    }

    private func initial(_ item: NotchMascotAccessory?) -> String {
        guard let item, let letter = name(item).first else { return "" }
        return String(letter).uppercased()
    }

    /// Opens what matters at first: in families, the one worn now and the
    /// two newest; sorted any other way, the first shelf.
    private func seed() {
        closedWhileFiltering = []
        switch sort {
        case .family:
            var open: Set<String> = ["family-\(NotchMascotWardrobeFamily.lab.rawValue)",
                                     "family-\(NotchMascotWardrobeFamily.mayhem.rawValue)"]
            if let worn = wornItem, let family = NotchMascotWardrobeFamily.of(worn) { open.insert("family-\(family.rawValue)") }
            opened = open
        case .rarity, .price, .name:
            opened = Set(shelves(from: passing(ignoringFamily: false)).prefix(1).map(\.id))
        }
    }

    private func isOpen(_ shelf: Shelf) -> Bool {
        filtering ? !closedWhileFiltering.contains(shelf.id) : opened.contains(shelf.id)
    }

    private func anchor(_ shelf: Shelf) -> String { "wardrobe-shelf-\(shelf.id)" }

    private func toggle(_ shelf: Shelf) {
        let opening = !isOpen(shelf)
        withAnimation(animation) {
            if filtering {
                if opening { _ = closedWhileFiltering.remove(shelf.id) } else { _ = closedWhileFiltering.insert(shelf.id) }
            } else {
                if opening { _ = opened.insert(shelf.id) } else { _ = opened.remove(shelf.id) }
            }
        }
        // A shelf opened low on the page is brought up so what it holds shows.
        guard opening, let scroll else { return }
        let id = anchor(shelf)
        let motion = animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(motion) { scroll.scrollTo(id, anchor: nil) }
        }
    }

    private func shelfView(_ shelf: Shelf) -> some View {
        let open = isOpen(shelf)
        let owned = shelf.items.filter(wearable).count
        return VStack(alignment: .leading, spacing: 8) {
            Button { toggle(shelf) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 12)
                    if let symbol = shelf.symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(shelf.tint ?? Color.accentColor)
                            .frame(width: 16)
                    } else if let tint = shelf.tint {
                        Circle().fill(tint).frame(width: 8, height: 8).frame(width: 16)
                    }
                    Text(shelf.title).font(.callout.weight(.semibold))
                    if shelf.isNew { NotchMascotNewBadge(text: text.newBadge) }
                    Spacer(minLength: 8)
                    Text("\(owned)/\(shelf.items.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(shelf.title), \(owned)/\(shelf.items.count)")
            .accessibilityAddTraits(.isHeader)
            if open {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 54), spacing: 8)],
                          alignment: .leading, spacing: 8) {
                    ForEach(shelf.items) { tile($0) }
                }
                .padding(.leading, 4)
                if let inspected, shelf.items.contains(inspected) {
                    NotchMascotWardrobeDetail(item: inspected, style: wearer.style, look: wearer.look,
                                              worn: wornItem == inspected, wearable: wearable(inspected),
                                              language: language, wear: { wear(inspected) },
                                              close: { withAnimation(animation) { self.inspected = nil } })
                        .transition(.opacity)
                }
            }
        }
        .id(anchor(shelf))
    }

    private func tile(_ item: NotchMascotAccessory) -> some View {
        let canWear = wearable(item)
        return NotchMascotWardrobeTile(accessory: item, worn: wornItem == item, inspected: inspected == item,
                                       unlocked: canWear, rarity: item.isPurchasable ? item.rarity : nil,
                                       isNew: item.isLabItem || item.isMayhemItem, title: tileTitle(item, canWear: canWear)) {
            if canWear { wear(item) }
            withAnimation(animation) { inspected = item }
        }
    }

    private func tileTitle(_ item: NotchMascotAccessory, canWear: Bool) -> String {
        var parts = [name(item)]
        if item.isPurchasable { parts.append(shopText.rarity(item.rarity)) }
        if !canWear {
            parts.append(item.isPurchasable ? "\(shopText.shopTag) · \(item.price)" : life.locked(at: item.unlockLevel))
        }
        return parts.joined(separator: " · ")
    }

    private func wear(_ item: NotchMascotAccessory) {
        guard item == .none || wearable(item) else { return }
        wearer.pick.wrappedValue = item.rawValue
        wearer.picked()
    }
}

// MARK: - A thing's card

/// What one thing is: its name and gag, its rarity and family, where it is
/// worn, what it does in a chain, and what can be done with it now: put on,
/// waited for a level, or bought when the shop shows it to this figure.
private struct NotchMascotWardrobeDetail: View {
    let item: NotchMascotAccessory
    let style: NotchMascotStyle
    let look: NotchMascotLook
    let worn: Bool
    let wearable: Bool
    let language: AppLanguage
    let wear: () -> Void
    let close: () -> Void
    @ObservedObject private var rpg = NotchMascotRPGState.shared

    private var text: NotchMascotWardrobeStrings { FeatureStrings.notchMascotWardrobe(language) }
    private var life: NotchMascotLifeStrings { FeatureStrings.notchMascotLife(language) }
    private var shopText: NotchMascotShopStrings { FeatureStrings.notchMascotShop(language) }

    private var previewLook: NotchMascotLook {
        var shown = look
        shown.style = style
        shown.accessory = item
        shown.form = nil
        shown.fusion = nil
        return shown
    }

    var body: some View {
        let family = NotchMascotWardrobeFamily.of(item)
        let facts = NotchMascotChainFacts(item)
        HStack(alignment: .top, spacing: 12) {
            NotchMascotView(look: previewLook, size: 30, idles: false)
                .frame(width: 30, height: 30)
                .frame(width: 64, height: 42)
                .background(Color.black, in: Capsule())
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(life.name(of: item)).font(.callout.weight(.semibold))
                    if item.isPurchasable {
                        Text(shopText.rarity(item.rarity))
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(NotchMascotWardrobeBrowser.tint(item.rarity).opacity(0.18), in: Capsule())
                            .foregroundStyle(NotchMascotWardrobeBrowser.tint(item.rarity))
                    }
                    if family?.isNew == true { NotchMascotNewBadge(text: text.newBadge) }
                    Spacer(minLength: 6)
                    Button(action: close) { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(text.close)
                        .accessibilityLabel(text.close)
                }
                if let gag = shopText.gag(of: item) {
                    Text(gag).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    if let family { fact(text.family(family), symbol: family.symbol) }
                    fact(text.spot(NotchMascotWardrobeSpot.of(item)), symbol: "figure.stand")
                }
                chainLines(facts)
                actions
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.secondary.opacity(0.18)))
    }

    private func fact(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.1), in: Capsule())
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func chainLines(_ facts: NotchMascotChainFacts) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if facts.isEmpty {
                Text(text.noChain).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                if let emits = facts.emits {
                    Label(text.throwsLine(emits), systemImage: "arrow.up.forward.circle")
                }
                ForEach(facts.reactions, id: \.self) { reaction in
                    Label(text.reactsLine(reaction.stimulus, then: reaction.thrown),
                          systemImage: reaction.thrown == nil ? "hand.raised.circle" : "arrow.triangle.branch")
                }
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            if worn {
                Label(text.worn, systemImage: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            } else if wearable {
                Button(text.wear, action: wear).controlSize(.small)
            } else if !item.isPurchasable {
                Label(life.locked(at: item.unlockLevel), systemImage: "lock.fill").foregroundStyle(.secondary)
            } else {
                purchase
            }
        }
        .font(.caption)
    }

    /// The thing is bought as the shop sells it: only while it is on show,
    /// to the figure the shop buys for, and with the gold for it.
    @ViewBuilder
    private var purchase: some View {
        let onShow = rpg.shopStock.contains(item)
        let forThisOne = rpg.shopFor == style
        let affordable = rpg.goldCoins >= item.price
        Label("\(item.price)", systemImage: "dollarsign.circle.fill")
            .monospacedDigit()
            .foregroundStyle(.yellow)
            .accessibilityLabel("\(shopText.gold) \(item.price)")
        if onShow && forThisOne {
            Button(shopText.buy) { _ = rpg.buy(item) }
                .controlSize(.small)
                .disabled(!affordable)
                .help(affordable ? shopText.buy : shopText.tooPoor)
                .accessibilityLabel("\(shopText.buy) \(life.name(of: item)), \(item.price)")
            Text(affordable ? text.inShop : shopText.tooPoor).foregroundStyle(.secondary)
        } else {
            Text(onShow ? text.shopForOther : text.notInShop)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Pieces

/// A wardrobe tile: the thing drawn small, its rarity as a stripe of colour,
/// a lock while it is out of reach, a check while it is worn and a spark on
/// the newest batches. Unlike the plain accessory tile it can be clicked
/// while locked, to open its card.
struct NotchMascotWardrobeTile: View {
    let accessory: NotchMascotAccessory
    /// A symbol drawn in place of the thing, for a choice that is not one.
    var symbol: String?
    let worn: Bool
    let inspected: Bool
    let unlocked: Bool
    let rarity: NotchMascotRarity?
    let isNew: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(worn ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.secondary)
                } else {
                    NotchMascotAccessoryVector(accessory: accessory, size: 28)
                        .opacity(unlocked ? 1.0 : 0.4)
                }
            }
            .frame(width: 44, height: 44)
            .overlay(alignment: .bottom) {
                if let rarity {
                    Capsule()
                        .fill(NotchMascotWardrobeBrowser.tint(rarity))
                        .frame(width: 20, height: 3)
                        .padding(.bottom, 3)
                }
            }
            .overlay(alignment: .topTrailing) {
                if !unlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                } else if worn {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(3)
                }
            }
            .overlay(alignment: .topLeading) {
                if isNew {
                    Image(systemName: "sparkle")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.pink)
                        .padding(4)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(worn ? Color.accentColor : (inspected ? Color.primary.opacity(0.5) : Color.clear),
                                  lineWidth: worn ? 2 : 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(worn ? .isSelected : [])
    }
}

/// The small "new" mark on the newest batches.
struct NotchMascotNewBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.pink))
    }
}

/// A filter chip: a title, how many things it holds, lit while chosen.
private struct NotchMascotWardrobeChip: View {
    let title: String
    var count: Int?
    let selected: Bool
    var symbol: String?
    var badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .semibold)) }
                Text(title)
                if let count {
                    Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                }
                if let badge { NotchMascotNewBadge(text: badge) }
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1), in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Lays chips out in rows, wrapping to the next row when one is full.
struct NotchMascotWardrobeFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var row: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += row + spacing
                x = 0
                row = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            row = max(row, size.height)
        }
        return CGSize(width: widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += row + spacing
                x = bounds.minX
                row = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

// MARK: - A menu for small places

/// What one figure may wear, as a menu by family, for small places such as
/// the Pocket Card, where stepping through two hundred things one at a time
/// would take all afternoon.
struct NotchMascotWardrobeMenu: View {
    let items: [NotchMascotAccessory]
    let current: NotchMascotAccessory
    let language: AppLanguage
    let choose: (NotchMascotAccessory) -> Void

    var body: some View {
        let life = FeatureStrings.notchMascotLife(language)
        let text = FeatureStrings.notchMascotWardrobe(language)
        let own = Set(items)
        Menu {
            option(.none, life: life)
            ForEach(NotchMascotWardrobeFamily.allCases) { family in
                let members = family.items.filter { own.contains($0) }
                if !members.isEmpty {
                    let title = "\(text.family(family)) (\(members.count))"
                    Menu(title) {
                        ForEach(members) { option($0, life: life) }
                    }
                }
            }
        } label: {
            Text(life.name(of: current))
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(life.name(of: current))
    }

    @ViewBuilder
    private func option(_ item: NotchMascotAccessory, life: NotchMascotLifeStrings) -> some View {
        Button { choose(item) } label: {
            if item == current {
                Label(life.name(of: item), systemImage: "checkmark")
            } else {
                Text(life.name(of: item))
            }
        }
    }
}

// MARK: - Chain reactions

/// How many chain reactions have been seen, and the rare things a chain can
/// set off: the ones seen lit with their marker, the rest still "???".
struct NotchMascotChainCard: View {
    let language: AppLanguage
    @State private var found = 0
    @State private var rares: Set<NotchMascotChainRare> = []

    private var text: NotchMascotWardrobeStrings { FeatureStrings.notchMascotWardrobe(language) }

    var body: some View {
        SettingsCard(title: text.chainTitle) {
            SettingsRow(symbol: "link", title: text.chainTitle, caption: text.chainHint) {
                Text(text.found(found)).foregroundStyle(.secondary).monospacedDigit()
            }
            SettingsRow(symbol: "sparkles", title: text.raresTitle) {
                Text("\(rares.count)/\(NotchMascotChainRare.allCases.count)").foregroundStyle(.secondary).monospacedDigit()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(NotchMascotChainRare.allCases, id: \.self) { rareTile($0) }
            }
            .padding(.leading, settingsRowTextInset)
        }
        .onAppear(perform: reload)
        // The log is written while the gang plays, with this page open or not.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)) { _ in reload() }
    }

    private func reload() {
        let count = NotchMascotChainLog.found().count
        let seen = NotchMascotChainLog.rares()
        if count != found { found = count }
        if seen != rares { rares = seen }
    }

    private func rareTile(_ rare: NotchMascotChainRare) -> some View {
        let known = rares.contains(rare)
        return HStack(spacing: 8) {
            Image(systemName: known ? "star.fill" : "questionmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(known ? Color.yellow : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(known ? rare.title(in: language) : text.unknownRare)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(known ? Color.primary : Color.secondary)
                    .lineLimit(1)
                if known {
                    Text(rare.gold > 0 ? "\(rare.marker) · \(text.rareGold(rare.gold))" : rare.marker)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(known ? Color.yellow.opacity(0.12) : Color.secondary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
