// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The games played with the desktop companion from its menu, and the
/// birthday it keeps.
struct NotchMascotGamesStrings {
    let play: String
    let roshambo: String
    let rock: String
    let paper: String
    let scissors: String
    let laser: String
    let fishing: String
    let hideAndSeek: String
    let birthday: String
    let birthdayHint: String
}

extension FeatureStrings {
    // swiftlint:disable:next function_body_length
    static func notchMascotGames(_ language: AppLanguage) -> NotchMascotGamesStrings {
        switch language {
        case .enUS:
            return .init(play: "Play", roshambo: "Rock, Paper, Scissors", rock: "Rock", paper: "Paper", scissors: "Scissors",
                         laser: "Laser Pointer", fishing: "Go Fishing", hideAndSeek: "Hide and Seek",
                         birthday: "Celebrate my birthday",
                         birthdayHint: "On this day the companion throws you a little party.")
        case .ptBR:
            return .init(play: "Brincar", roshambo: "Pedra, papel e tesoura", rock: "Pedra", paper: "Papel", scissors: "Tesoura",
                         laser: "Ponteiro laser", fishing: "Ir pescar", hideAndSeek: "Esconde-esconde",
                         birthday: "Comemorar meu aniversário",
                         birthdayHint: "Neste dia o companheiro faz uma festinha para você.")
        case .tr:
            return .init(play: "Oyna", roshambo: "Taş, Kâğıt, Makas", rock: "Taş", paper: "Kâğıt", scissors: "Makas",
                         laser: "Lazer işaretçi", fishing: "Balığa çık", hideAndSeek: "Saklambaç",
                         birthday: "Doğum günümü kutla",
                         birthdayHint: "Bu gün arkadaşın sana küçük bir parti verir.")
        case .ru:
            return .init(play: "Играть", roshambo: "Камень, ножницы, бумага", rock: "Камень", paper: "Бумага",
                         scissors: "Ножницы", laser: "Лазерная указка", fishing: "На рыбалку", hideAndSeek: "Прятки",
                         birthday: "Отмечать мой день рождения",
                         birthdayHint: "В этот день компаньон устраивает для вас маленький праздник.")
        case .es:
            return .init(play: "Jugar", roshambo: "Piedra, papel o tijera", rock: "Piedra", paper: "Papel", scissors: "Tijera",
                         laser: "Puntero láser", fishing: "Ir a pescar", hideAndSeek: "Escondite",
                         birthday: "Celebrar mi cumpleaños",
                         birthdayHint: "Ese día el compañero te monta una pequeña fiesta.")
        case .de:
            return .init(play: "Spielen", roshambo: "Schere, Stein, Papier", rock: "Stein", paper: "Papier", scissors: "Schere",
                         laser: "Laserpointer", fishing: "Angeln gehen", hideAndSeek: "Verstecken",
                         birthday: "Meinen Geburtstag feiern",
                         birthdayHint: "An diesem Tag schmeißt der Begleiter dir eine kleine Party.")
        case .fr:
            return .init(play: "Jouer", roshambo: "Pierre, feuille, ciseaux", rock: "Pierre", paper: "Feuille",
                         scissors: "Ciseaux", laser: "Pointeur laser", fishing: "Aller pêcher", hideAndSeek: "Cache-cache",
                         birthday: "Fêter mon anniversaire",
                         birthdayHint: "Ce jour-là, le compagnon vous organise une petite fête.")
        case .it:
            return .init(play: "Gioca", roshambo: "Sasso, carta, forbici", rock: "Sasso", paper: "Carta", scissors: "Forbici",
                         laser: "Puntatore laser", fishing: "Vai a pescare", hideAndSeek: "Nascondino",
                         birthday: "Festeggia il mio compleanno",
                         birthdayHint: "Quel giorno il compagno ti organizza una piccola festa.")
        case .ja:
            return .init(play: "遊ぶ", roshambo: "じゃんけん", rock: "グー", paper: "パー", scissors: "チョキ",
                         laser: "レーザーポインター", fishing: "釣りに行く", hideAndSeek: "かくれんぼ",
                         birthday: "誕生日を祝う",
                         birthdayHint: "その日はコンパニオンが小さなパーティーを開いてくれます。")
        case .ko:
            return .init(play: "놀기", roshambo: "가위바위보", rock: "바위", paper: "보", scissors: "가위",
                         laser: "레이저 포인터", fishing: "낚시하기", hideAndSeek: "숨바꼭질",
                         birthday: "내 생일 축하하기",
                         birthdayHint: "그날에는 동반자가 작은 파티를 열어 줍니다.")
        case .zhHans:
            return .init(play: "玩耍", roshambo: "石头剪刀布", rock: "石头", paper: "布", scissors: "剪刀",
                         laser: "激光笔", fishing: "去钓鱼", hideAndSeek: "捉迷藏",
                         birthday: "庆祝我的生日",
                         birthdayHint: "这一天伙伴会为你办一场小派对。")
        case .zhTW:
            return .init(play: "玩耍", roshambo: "剪刀石頭布", rock: "石頭", paper: "布", scissors: "剪刀",
                         laser: "雷射筆", fishing: "去釣魚", hideAndSeek: "捉迷藏",
                         birthday: "慶祝我的生日",
                         birthdayHint: "這一天夥伴會為你辦一場小派對。")
        case .zhHK:
            return .init(play: "玩", roshambo: "包剪揼", rock: "揼", paper: "包", scissors: "剪",
                         laser: "激光筆", fishing: "去釣魚", hideAndSeek: "捉迷藏",
                         birthday: "慶祝我嘅生日",
                         birthdayHint: "呢日夥伴會幫你搞個小派對。")
        case .sk:
            return .init(play: "Hrať sa", roshambo: "Kameň, papier, nožnice", rock: "Kameň", paper: "Papier",
                         scissors: "Nožnice", laser: "Laserové ukazovadlo", fishing: "Ísť na ryby", hideAndSeek: "Schovávačka",
                         birthday: "Osláviť moje narodeniny",
                         birthdayHint: "V tento deň ti spoločník pripraví malú oslavu.")
        case .uk:
            return .init(play: "Грати", roshambo: "Камінь, ножиці, папір", rock: "Камінь", paper: "Папір",
                         scissors: "Ножиці", laser: "Лазерна указка", fishing: "На риболовлю", hideAndSeek: "Хованки",
                         birthday: "Святкувати мій день народження",
                         birthdayHint: "Цього дня компаньйон влаштовує для вас маленьке свято.")
        }
    }
}
