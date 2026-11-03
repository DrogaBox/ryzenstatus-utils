// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The line under a cheat's banner, in the arcade's capitals.
struct NotchMascotCheatStrings {
    let activated: String
}

extension FeatureStrings {
    static func notchMascotCheats(_ language: AppLanguage) -> NotchMascotCheatStrings {
        switch language {
        case .enUS: return .init(activated: "CHEAT ACTIVATED")
        case .ptBR: return .init(activated: "TRAPAÇA ATIVADA")
        case .tr: return .init(activated: "HİLE ETKİN")
        case .ru: return .init(activated: "ЧИТ АКТИВИРОВАН")
        case .es: return .init(activated: "TRUCO ACTIVADO")
        case .de: return .init(activated: "CHEAT AKTIVIERT")
        case .fr: return .init(activated: "TRICHE ACTIVÉE")
        case .it: return .init(activated: "TRUCCO ATTIVATO")
        case .ja: return .init(activated: "チート発動")
        case .ko: return .init(activated: "치트 발동")
        case .zhHans: return .init(activated: "秘籍已激活")
        case .zhTW: return .init(activated: "密技已啟動")
        case .zhHK: return .init(activated: "秘技已啟動")
        case .sk: return .init(activated: "CHEAT AKTIVOVANÝ")
        case .uk: return .init(activated: "ЧИТ АКТИВОВАНО")
        }
    }
}
