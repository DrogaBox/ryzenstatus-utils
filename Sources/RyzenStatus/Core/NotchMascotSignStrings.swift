// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// What the White Rabbit's cardboard sign says in each row, in capitals as
/// the comic letters it. In Spanish the sheet keeps the author's own
/// lettering; every other language is written onto the blank sign.
struct NotchMascotSignStrings {
    let hello: String
    let going: String
    let howsItGoing: String
    let yes: String
    let error: String
    let thinking: String
    let onTheWay: String
    let done: String
    let takeALook: String

    /// The sign for `state`, its lines apart; running, it points the way.
    func text(for state: NotchMascotSpriteState) -> String {
        switch state {
        case .idle: return hello
        case .runRight: return going + " >"
        case .runLeft: return "< " + going
        case .waving: return howsItGoing
        case .jumping: return yes
        case .failed: return error
        case .waiting: return thinking
        case .running: return onTheWay
        case .review: return done + "\n" + takeALook
        }
    }
}

extension FeatureStrings {
    static func notchMascotSign(_ language: AppLanguage) -> NotchMascotSignStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension NotchMascotSignStrings {
    static let enUS = NotchMascotSignStrings(
        hello: "HI",
        going: "GOING",
        howsItGoing: "WHAT'S UP",
        yes: "YES!",
        error: "ERROR",
        thinking: "THINKING",
        onTheWay: "ON MY WAY",
        done: "DONE!",
        takeALook: "CHECK IT")
    static let ptBR = NotchMascotSignStrings(
        hello: "OLÁ",
        going: "VOU",
        howsItGoing: "TUDO BEM?",
        yes: "SIM!",
        error: "ERRO",
        thinking: "PENSANDO",
        onTheWay: "A CAMINHO",
        done: "PRONTO!",
        takeALook: "CONFIRA")
    static let tr = NotchMascotSignStrings(
        hello: "MERHABA",
        going: "GİDİYORUM",
        howsItGoing: "NASILSIN?",
        yes: "EVET!",
        error: "HATA",
        thinking: "DÜŞÜNÜYOR",
        onTheWay: "YOLDAYIM",
        done: "TAMAM!",
        takeALook: "BAK")
    static let ru = NotchMascotSignStrings(
        hello: "ПРИВЕТ",
        going: "ИДУ",
        howsItGoing: "КАК ДЕЛА?",
        yes: "ДА!",
        error: "ОШИБКА",
        thinking: "ДУМАЮ",
        onTheWay: "УЖЕ ИДУ",
        done: "ГОТОВО!",
        takeALook: "ПРОВЕРЬ")
    static let es = NotchMascotSignStrings(
        hello: "HOLA",
        going: "VOY",
        howsItGoing: "QUÉ TAL",
        yes: "¡SÍ!",
        error: "ERROR",
        thinking: "PENSANDO",
        onTheWay: "EN CAMINO",
        done: "¡LISTO!",
        takeALook: "REVISÁ")
    static let sk = NotchMascotSignStrings(
        hello: "AHOJ",
        going: "IDEM",
        howsItGoing: "ČO NOVÉ?",
        yes: "ÁNO!",
        error: "CHYBA",
        thinking: "PREMÝŠĽAM",
        onTheWay: "UŽ IDEM",
        done: "HOTOVO!",
        takeALook: "POZRI")
    static let de = NotchMascotSignStrings(
        hello: "HALLO",
        going: "LOS",
        howsItGoing: "WIE GEHT'S?",
        yes: "JA!",
        error: "FEHLER",
        thinking: "GRÜBEL…",
        onTheWay: "UNTERWEGS",
        done: "FERTIG!",
        takeALook: "SCHAU MAL")
    static let fr = NotchMascotSignStrings(
        hello: "SALUT",
        going: "J'Y VAIS",
        howsItGoing: "ÇA VA ?",
        yes: "OUI !",
        error: "ERREUR",
        thinking: "JE RÉFLÉCHIS",
        onTheWay: "EN ROUTE",
        done: "FINI !",
        takeALook: "REGARDE")
    static let it = NotchMascotSignStrings(
        hello: "CIAO",
        going: "VADO",
        howsItGoing: "COME VA?",
        yes: "SÌ!",
        error: "ERRORE",
        thinking: "CI PENSO",
        onTheWay: "ARRIVO",
        done: "FATTO!",
        takeALook: "GUARDA")
    static let ja = NotchMascotSignStrings(
        hello: "やあ",
        going: "いくよ",
        howsItGoing: "げんき？",
        yes: "やった！",
        error: "エラー",
        thinking: "かんがえ中",
        onTheWay: "いま行く",
        done: "できた！",
        takeALook: "見てね")
    static let ko = NotchMascotSignStrings(
        hello: "안녕",
        going: "간다",
        howsItGoing: "잘 지내?",
        yes: "좋아!",
        error: "오류",
        thinking: "생각 중",
        onTheWay: "가는 중",
        done: "완료!",
        takeALook: "확인해")
    static let zhHans = NotchMascotSignStrings(
        hello: "你好",
        going: "走啦",
        howsItGoing: "还好吗",
        yes: "好耶！",
        error: "出错",
        thinking: "思考中",
        onTheWay: "在路上",
        done: "好了！",
        takeALook: "看看吧")
    static let zhTW = NotchMascotSignStrings(
        hello: "你好",
        going: "走囉",
        howsItGoing: "還好嗎",
        yes: "好耶！",
        error: "出錯",
        thinking: "思考中",
        onTheWay: "在路上",
        done: "好了！",
        takeALook: "看看吧")
    static let zhHK = NotchMascotSignStrings(
        hello: "你好",
        going: "去啦",
        howsItGoing: "點呀",
        yes: "好嘢！",
        error: "出錯",
        thinking: "諗緊嘢",
        onTheWay: "嚟緊",
        done: "搞掂！",
        takeALook: "睇吓")
    static let uk = NotchMascotSignStrings(
        hello: "ПРИВІТ",
        going: "ЙДУ",
        howsItGoing: "ЯК СПРАВИ?",
        yes: "ТАК!",
        error: "ПОМИЛКА",
        thinking: "ДУМАЮ",
        onTheWay: "УЖЕ ЙДУ",
        done: "ГОТОВО!",
        takeALook: "ПОДИВИСЬ")
}
