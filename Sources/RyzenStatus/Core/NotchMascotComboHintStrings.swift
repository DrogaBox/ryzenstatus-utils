// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The hint under the companion's preview in Settings: what the thing it
/// wears makes a combo with when the friend wears the other, the ones found
/// by name and the rest counted, with one of them to try next.
struct NotchMascotComboHintStrings {
    /// "%1$@ pairs with %2$@." — the thing worn, then the partners found.
    let known: String
    /// "%1$@ pairs with %2$d things." — nothing found yet.
    let count: String
    /// "%1$d still to find — try %2$@ on the friend."
    let more: String

    /// The whole hint for `item`, with `found` named and `hidden` left, and
    /// `suggestion` the next one to try.
    func hint(item: String, found: [String], hidden: Int, suggestion: String?) -> String {
        var text = found.isEmpty
            ? String(format: count, item, found.count + hidden)
            : String(format: known, item, found.joined(separator: ", "))
        if hidden > 0, let suggestion { text += " " + String(format: more, hidden, suggestion) }
        return text
    }
}

extension FeatureStrings {
    static func notchMascotComboHint(_ language: AppLanguage) -> NotchMascotComboHintStrings {
        switch language {
        case .enUS: return .init(known: "%1$@ pairs with %2$@.", count: "%1$@ pairs with %2$d things.",
                                 more: "%1$d still to find — try %2$@ on the friend.")
        case .ptBR: return .init(known: "%1$@ combina com %2$@.", count: "%1$@ combina com %2$d coisas.",
                                 more: "Faltam %1$d — experimente %2$@ no amigo.")
        case .tr: return .init(known: "%1$@ şunlarla uyumlu: %2$@.", count: "%1$@ %2$d şeyle uyumlu.",
                               more: "%1$d tane daha var — arkadaşa %2$@ dene.")
        case .ru: return .init(known: "%1$@ сочетается с: %2$@.", count: "%1$@ сочетается с %2$d вещами.",
                               more: "Ещё %1$d не найдено — наденьте другу %2$@.")
        case .es: return .init(known: "%1$@ combina con %2$@.", count: "%1$@ combina con %2$d cosas.",
                               more: "Quedan %1$d por descubrir: prueba %2$@ en el amigo.")
        case .de: return .init(known: "%1$@ passt zu %2$@.", count: "%1$@ passt zu %2$d Dingen.",
                               more: "Noch %1$d zu entdecken – probier %2$@ beim Freund.")
        case .fr: return .init(known: "%1$@ se combine avec %2$@.", count: "%1$@ se combine avec %2$d objets.",
                               more: "Encore %1$d à découvrir — essayez %2$@ sur l’ami.")
        case .it: return .init(known: "%1$@ si abbina con %2$@.", count: "%1$@ si abbina con %2$d cose.",
                               more: "Ne restano %1$d da scoprire: prova %2$@ sull’amico.")
        case .ja: return .init(known: "%1$@ は %2$@ と組み合わせられます。", count: "%1$@ は %2$d 個のアイテムと組み合わせられます。",
                               more: "あと %1$d 個 — 友だちに %2$@ を着せてみて。")
        case .ko: return .init(known: "%1$@은(는) %2$@와(과) 어울립니다.", count: "%1$@은(는) %2$d개의 아이템과 어울립니다.",
                               more: "아직 %1$d개 남았어요 — 친구에게 %2$@을(를) 입혀 보세요.")
        case .zhHans: return .init(known: "%1$@ 可与 %2$@ 组合。", count: "%1$@ 可与 %2$d 件物品组合。",
                                   more: "还有 %1$d 个待发现——给朋友戴上 %2$@ 试试。")
        case .zhTW: return .init(known: "%1$@ 可與 %2$@ 組合。", count: "%1$@ 可與 %2$d 件物品組合。",
                                 more: "還有 %1$d 個待發現——讓朋友戴上 %2$@ 試試。")
        case .zhHK: return .init(known: "%1$@ 可以同 %2$@ 組合。", count: "%1$@ 可以同 %2$d 件物品組合。",
                                 more: "仲有 %1$d 個未發現——俾朋友戴 %2$@ 試吓。")
        case .sk: return .init(known: "%1$@ sa kombinuje s: %2$@.", count: "%1$@ sa kombinuje s %2$d vecami.",
                               more: "Ešte %1$d na objavenie — skús kamarátovi %2$@.")
        case .uk: return .init(known: "%1$@ поєднується з: %2$@.", count: "%1$@ поєднується з %2$d речами.",
                               more: "Ще %1$d не знайдено — вдягніть другові %2$@.")
        }
    }
}
extension FeatureStrings {
    /// The button under the companion's preview that has it try what it wears.
    static func notchMascotItemUseButton(_ language: AppLanguage) -> String {
        switch language {
        case .enUS: return "Use item"
        case .ptBR: return "Usar item"
        case .tr: return "Eşyayı kullan"
        case .ru: return "Использовать"
        case .es: return "Usar objeto"
        case .de: return "Benutzen"
        case .fr: return "Utiliser"
        case .it: return "Usa oggetto"
        case .ja: return "アイテムを使う"
        case .ko: return "아이템 사용"
        case .zhHans: return "使用物品"
        case .zhTW: return "使用物品"
        case .zhHK: return "使用物品"
        case .sk: return "Použiť vec"
        case .uk: return "Використати"
        }
    }
}
