// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Two companions out on the desktop fused into one: the menu that asks
/// for it or undoes it, the three shouts of the dance, and what the fused
/// one calls itself, done well or gone wrong.
struct NotchMascotFusionStrings {
    /// The menu item that lists the others it can fuse with.
    let fuseWith: String
    /// Said in that menu when no other is out to fuse with.
    let nobody: String
    /// The fused one's menu item that splits it in two again.
    let splitApart: String
    /// The three beats of the dance, shouted by both.
    let fu: String
    let sion: String
    let ha: String
    /// The fused one introduces itself; `%@` is its name.
    let intro: String
    /// A fusion gone wrong wonders what it is; `%@` is its name.
    let flop: String

    func introducing(_ name: String) -> String { String(format: intro, name) }
    func flopped(_ name: String) -> String { String(format: flop, name) }
}

extension FeatureStrings {
    // swiftlint:disable:next function_body_length
    static func notchMascotFusion(_ language: AppLanguage) -> NotchMascotFusionStrings {
        switch language {
        case .enUS:
            return .init(fuseWith: "Fuse With", nobody: "Nobody Out to Fuse With", splitApart: "Split Apart",
                         fu: "FU…", sion: "SION…", ha: "HA!", intro: "I am %@!", flop: "%@…?")
        case .ptBR:
            return .init(fuseWith: "Fundir com", nobody: "Ninguém por perto para fundir", splitApart: "Separar",
                         fu: "FU…", sion: "SÃO…", ha: "HÁ!", intro: "Eu sou %@!", flop: "%@…?")
        case .tr:
            return .init(fuseWith: "Şununla birleş", nobody: "Birleşecek kimse yok", splitApart: "Ayrıl",
                         fu: "FÜ…", sion: "ZYON…", ha: "HA!", intro: "Ben %@!", flop: "%@…?")
        case .ru:
            return .init(fuseWith: "Слиться с", nobody: "Не с кем слиться", splitApart: "Разделиться",
                         fu: "ФЬЮ…", sion: "ЖЕН…", ha: "ХА!", intro: "Я — %@!", flop: "%@…?")
        case .es:
            return .init(fuseWith: "Fusionarse con", nobody: "No hay nadie para fusionarse", splitApart: "Separarse",
                         fu: "FU…", sion: "SIÓN…", ha: "¡HA!", intro: "¡Soy %@!", flop: "¿%@…?")
        case .de:
            return .init(fuseWith: "Fusionieren mit", nobody: "Niemand da zum Fusionieren", splitApart: "Trennen",
                         fu: "FU…", sion: "SION…", ha: "HA!", intro: "Ich bin %@!", flop: "%@…?")
        case .fr:
            return .init(fuseWith: "Fusionner avec", nobody: "Personne avec qui fusionner", splitApart: "Se séparer",
                         fu: "FU…", sion: "SION…", ha: "HA !", intro: "Je suis %@ !", flop: "%@… ?")
        case .it:
            return .init(fuseWith: "Fondersi con", nobody: "Nessuno con cui fondersi", splitApart: "Separarsi",
                         fu: "FU…", sion: "SIONE…", ha: "HA!", intro: "Sono %@!", flop: "%@…?")
        case .ja:
            return .init(fuseWith: "フュージョンする", nobody: "フュージョンできる相手がいない", splitApart: "分離する",
                         fu: "フュー…", sion: "ジョン…", ha: "はっ！", intro: "おれは%@だ！", flop: "%@…？")
        case .ko:
            return .init(fuseWith: "퓨전하기", nobody: "퓨전할 상대가 없어요", splitApart: "분리하기",
                         fu: "퓨…", sion: "전…", ha: "핫!", intro: "나는 %@다!", flop: "%@…?")
        case .zhHans:
            return .init(fuseWith: "合体", nobody: "没有可以合体的伙伴", splitApart: "分开",
                         fu: "合…", sion: "体…", ha: "哈！", intro: "我是%@！", flop: "%@…？")
        case .zhTW:
            return .init(fuseWith: "合體", nobody: "沒有可以合體的夥伴", splitApart: "分開",
                         fu: "合…", sion: "體…", ha: "哈！", intro: "我是%@！", flop: "%@…？")
        case .zhHK:
            return .init(fuseWith: "合體", nobody: "冇夥伴可以合體", splitApart: "分開",
                         fu: "合…", sion: "體…", ha: "哈！", intro: "我係%@！", flop: "%@…？")
        case .sk:
            return .init(fuseWith: "Spojiť sa s", nobody: "Nie je s kým sa spojiť", splitApart: "Rozdeliť sa",
                         fu: "FÚ…", sion: "ZIA…", ha: "HA!", intro: "Som %@!", flop: "%@…?")
        case .uk:
            return .init(fuseWith: "Злитися з", nobody: "Нема з ким злитися", splitApart: "Розділитися",
                         fu: "ФЬЮ…", sion: "ЖН…", ha: "ХА!", intro: "Я — %@!", flop: "%@…?")
        }
    }
}
