// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Strings for the session lowest and highest readings under the panel's
/// CPU row. Same contract as the other FeatureStrings structs: memberwise
/// init with labeled arguments in declaration order, one static per
/// language, all in this file. Units (°C, W, GHz, RPM) stay as they are.
struct SessionPeakStrings {
    /// "Since 21:04"; the argument is the start time in the user's format.
    let sinceFormat: String
    let temperature: String
    let power: String
    let clock: String
    let fan: String
    let reset: String
    let resetHelp: String

    func since(_ time: String) -> String {
        String(format: sinceFormat, time)
    }
}

extension FeatureStrings {
    static func sessionPeaks(_ language: AppLanguage) -> SessionPeakStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .sk: return .sk
        case .uk: return .uk
        }
    }
}

private extension SessionPeakStrings {
    static let enUS = SessionPeakStrings(
        sinceFormat: "Since %@",
        temperature: "Temperature",
        power: "Power",
        clock: "Clock",
        fan: "Fan",
        reset: "Reset",
        resetHelp: "Forget these readings and start again from now")

    static let ptBR = SessionPeakStrings(
        sinceFormat: "Desde %@",
        temperature: "Temperatura",
        power: "Potência",
        clock: "Frequência",
        fan: "Ventoinha",
        reset: "Redefinir",
        resetHelp: "Esquecer estas leituras e recomeçar a partir de agora")

    static let tr = SessionPeakStrings(
        sinceFormat: "%@ saatinden beri",
        temperature: "Sıcaklık",
        power: "Güç",
        clock: "Saat hızı",
        fan: "Fan",
        reset: "Sıfırla",
        resetHelp: "Bu değerleri unut ve şimdiden yeniden başla")

    static let ru = SessionPeakStrings(
        sinceFormat: "С %@",
        temperature: "Температура",
        power: "Мощность",
        clock: "Частота",
        fan: "Вентилятор",
        reset: "Сбросить",
        resetHelp: "Забыть эти значения и начать заново с этого момента")

    static let es = SessionPeakStrings(
        sinceFormat: "Desde %@",
        temperature: "Temperatura",
        power: "Potencia",
        clock: "Frecuencia",
        fan: "Ventilador",
        reset: "Restablecer",
        resetHelp: "Olvidar estas lecturas y empezar de nuevo desde ahora")

    static let de = SessionPeakStrings(
        sinceFormat: "Seit %@",
        temperature: "Temperatur",
        power: "Leistung",
        clock: "Takt",
        fan: "Lüfter",
        reset: "Zurücksetzen",
        resetHelp: "Diese Werte verwerfen und ab jetzt neu beginnen")

    static let fr = SessionPeakStrings(
        sinceFormat: "Depuis %@",
        temperature: "Température",
        power: "Puissance",
        clock: "Fréquence",
        fan: "Ventilateur",
        reset: "Réinitialiser",
        resetHelp: "Oublier ces valeurs et recommencer à partir de maintenant")

    static let it = SessionPeakStrings(
        sinceFormat: "Dalle %@",
        temperature: "Temperatura",
        power: "Potenza",
        clock: "Frequenza",
        fan: "Ventola",
        reset: "Azzera",
        resetHelp: "Dimentica questi valori e ricomincia da adesso")

    static let ja = SessionPeakStrings(
        sinceFormat: "%@ 以降",
        temperature: "温度",
        power: "電力",
        clock: "クロック",
        fan: "ファン",
        reset: "リセット",
        resetHelp: "これらの値を消去して、今から計測し直します")

    static let ko = SessionPeakStrings(
        sinceFormat: "%@ 이후",
        temperature: "온도",
        power: "전력",
        clock: "클럭",
        fan: "팬",
        reset: "재설정",
        resetHelp: "이 값을 지우고 지금부터 다시 측정합니다")

    static let zhHans = SessionPeakStrings(
        sinceFormat: "自 %@ 起",
        temperature: "温度",
        power: "功率",
        clock: "频率",
        fan: "风扇",
        reset: "重置",
        resetHelp: "清除这些读数，从现在起重新统计")

    static let zhTW = SessionPeakStrings(
        sinceFormat: "自 %@ 起",
        temperature: "溫度",
        power: "功耗",
        clock: "時脈",
        fan: "風扇",
        reset: "重設",
        resetHelp: "清除這些讀數，從現在起重新統計")

    static let zhHK = SessionPeakStrings(
        sinceFormat: "自 %@ 起",
        temperature: "溫度",
        power: "功耗",
        clock: "時脈",
        fan: "風扇",
        reset: "重設",
        resetHelp: "清除這些讀數，由現在起重新統計")

    static let sk = SessionPeakStrings(
        sinceFormat: "Od %@",
        temperature: "Teplota",
        power: "Príkon",
        clock: "Frekvencia",
        fan: "Ventilátor",
        reset: "Vynulovať",
        resetHelp: "Zabudnúť tieto hodnoty a začať odznova od tejto chvíle")

    static let uk = SessionPeakStrings(
        sinceFormat: "З %@",
        temperature: "Температура",
        power: "Потужність",
        clock: "Частота",
        fan: "Вентилятор",
        reset: "Скинути",
        resetHelp: "Забути ці значення й почати заново з цієї миті")
}
