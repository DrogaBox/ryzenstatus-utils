// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The other companions that come by the desktop on visits: how often, how
/// many at once, and what a guest's menu offers.
struct NotchMascotGangStrings {
    let visits: String
    let visitsCaption: String
    let off: String
    let rare: String
    let normal: String
    let frequent: String
    let atOnce: String
    let stayLonger: String
    let sayGoodbye: String
    let giveTreat: String
    /// The "how many at once" choice that lets every figure come.
    var everyone = "All"

    func frequency(_ visits: NotchMascotGangVisits) -> String {
        switch visits {
        case .off: return off
        case .rare: return rare
        case .normal: return normal
        case .frequent: return frequent
        }
    }
}

extension FeatureStrings {
    // swiftlint:disable:next function_body_length
    static func notchMascotGang(_ language: AppLanguage) -> NotchMascotGangStrings {
        switch language {
        case .enUS:
            return .init(visits: "Visits",
                         visitsCaption: "Other companions drop by the desktop now and then, play with yours and with each other, and go on their way after a few minutes.",
                         off: "Off", rare: "Rare", normal: "Normal", frequent: "Frequent", atOnce: "Max at once",
                         stayLonger: "Stay Longer", sayGoodbye: "Say Goodbye", giveTreat: "Give a Treat", everyone: "All")
        case .ptBR:
            return .init(visits: "Visitas",
                         visitsCaption: "Outros companheiros aparecem na mesa de vez em quando, brincam com o seu e entre si, e vão embora depois de alguns minutos.",
                         off: "Não", rare: "Raras", normal: "Normais", frequent: "Frequentes", atOnce: "Máximo ao mesmo tempo",
                         stayLonger: "Ficar mais", sayGoodbye: "Despedir-se", giveTreat: "Dar um petisco", everyone: "Todos")
        case .tr:
            return .init(visits: "Ziyaretler",
                         visitsCaption: "Başka arkadaşlar ara sıra masaüstüne uğrar, seninkiyle ve birbirleriyle oynar, birkaç dakika sonra yollarına giderler.",
                         off: "Kapalı", rare: "Seyrek", normal: "Normal", frequent: "Sık", atOnce: "Aynı anda en fazla",
                         stayLonger: "Biraz daha kal", sayGoodbye: "Hoşça kal de", giveTreat: "İkram ver", everyone: "Hepsi")
        case .ru:
            return .init(visits: "Гости",
                         visitsCaption: "Другие компаньоны время от времени заглядывают на рабочий стол, играют с вашим и друг с другом и через несколько минут уходят.",
                         off: "Нет", rare: "Редко", normal: "Обычно", frequent: "Часто", atOnce: "Не больше одновременно",
                         stayLonger: "Остаться подольше", sayGoodbye: "Попрощаться", giveTreat: "Угостить", everyone: "Все")
        case .es:
            return .init(visits: "Visitas",
                         visitsCaption: "Otros compañeros pasan por el escritorio de vez en cuando, juegan con el tuyo y entre ellos, y se van a los pocos minutos.",
                         off: "No", rare: "Pocas", normal: "Normal", frequent: "Muchas", atOnce: "Máximo a la vez",
                         stayLonger: "Quedarse más", sayGoodbye: "Despedirse", giveTreat: "Darle algo rico", everyone: "Todos")
        case .de:
            return .init(visits: "Besuche",
                         visitsCaption: "Andere Begleiter schauen ab und zu auf dem Schreibtisch vorbei, spielen mit deinem und miteinander und ziehen nach ein paar Minuten weiter.",
                         off: "Aus", rare: "Selten", normal: "Normal", frequent: "Häufig", atOnce: "Höchstens gleichzeitig",
                         stayLonger: "Länger bleiben", sayGoodbye: "Verabschieden", giveTreat: "Leckerli geben", everyone: "Alle")
        case .fr:
            return .init(visits: "Visites",
                         visitsCaption: "D’autres compagnons passent sur le bureau de temps en temps, jouent avec le vôtre et entre eux, puis repartent au bout de quelques minutes.",
                         off: "Non", rare: "Rares", normal: "Normales", frequent: "Fréquentes", atOnce: "Maximum à la fois",
                         stayLonger: "Rester plus longtemps", sayGoodbye: "Dire au revoir", giveTreat: "Offrir une friandise", everyone: "Tous")
        case .it:
            return .init(visits: "Visite",
                         visitsCaption: "Altri compagni passano sulla scrivania ogni tanto, giocano con il tuo e tra loro, e se ne vanno dopo qualche minuto.",
                         off: "No", rare: "Rare", normal: "Normali", frequent: "Frequenti", atOnce: "Massimo insieme",
                         stayLonger: "Resta ancora", sayGoodbye: "Saluta", giveTreat: "Dai un premio", everyone: "Tutti")
        case .ja:
            return .init(visits: "おきゃくさん",
                         visitsCaption: "ほかのコンパニオンがときどきデスクトップに遊びに来て、あなたのコンパニオンや仲間同士で遊び、数分すると帰っていきます。",
                         off: "オフ", rare: "まれ", normal: "ふつう", frequent: "よく", atOnce: "同時に最大",
                         stayLonger: "もっといて", sayGoodbye: "さよならする", giveTreat: "おやつをあげる", everyone: "全員")
        case .ko:
            return .init(visits: "손님",
                         visitsCaption: "다른 동반자들이 가끔 데스크톱에 들러 당신의 동반자와, 또 서로 놀다가 몇 분 뒤에 떠납니다.",
                         off: "끔", rare: "드물게", normal: "보통", frequent: "자주", atOnce: "동시에 최대",
                         stayLonger: "더 있다 가기", sayGoodbye: "작별 인사", giveTreat: "간식 주기", everyone: "모두")
        case .zhHans:
            return .init(visits: "来访",
                         visitsCaption: "其他伙伴不时来桌面串门，和你的伙伴以及彼此一起玩，几分钟后再离开。",
                         off: "关闭", rare: "偶尔", normal: "一般", frequent: "经常", atOnce: "同时最多",
                         stayLonger: "多待一会儿", sayGoodbye: "说再见", giveTreat: "给点零食", everyone: "全部")
        case .zhTW:
            return .init(visits: "來訪",
                         visitsCaption: "其他夥伴不時來桌面串門子，和你的夥伴以及彼此一起玩，幾分鐘後再離開。",
                         off: "關閉", rare: "偶爾", normal: "一般", frequent: "經常", atOnce: "同時最多",
                         stayLonger: "多待一會兒", sayGoodbye: "說再見", giveTreat: "給點零食", everyone: "全部")
        case .zhHK:
            return .init(visits: "探訪",
                         visitsCaption: "其他夥伴間中會嚟桌面探你，同你嘅夥伴同埋大家一齊玩，幾分鐘後先走。",
                         off: "關", rare: "間中", normal: "一般", frequent: "經常", atOnce: "同時最多",
                         stayLonger: "留耐啲", sayGoodbye: "講拜拜", giveTreat: "俾啲零食", everyone: "全部")
        case .sk:
            return .init(visits: "Návštevy",
                         visitsCaption: "Iní spoločníci sa z času na čas zastavia na ploche, hrajú sa s tvojím aj medzi sebou a po pár minútach odídu.",
                         off: "Vyp.", rare: "Zriedka", normal: "Bežne", frequent: "Často", atOnce: "Najviac naraz",
                         stayLonger: "Zostaň dlhšie", sayGoodbye: "Rozlúčiť sa", giveTreat: "Dať maškrtu", everyone: "Všetky")
        case .uk:
            return .init(visits: "Гості",
                         visitsCaption: "Інші компаньйони час від часу заходять на робочий стіл, граються з вашим і між собою та за кілька хвилин ідуть далі.",
                         off: "Ні", rare: "Рідко", normal: "Звичайно", frequent: "Часто", atOnce: "Найбільше одночасно",
                         stayLonger: "Залишитися довше", sayGoodbye: "Попрощатися", giveTreat: "Пригостити", everyone: "Усі")
        }
    }
}
