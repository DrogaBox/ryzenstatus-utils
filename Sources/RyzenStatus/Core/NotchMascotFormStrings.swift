// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Strings for the companion's transformations. Same contract as the other
/// FeatureStrings structs: memberwise init with labeled arguments in
/// declaration order, one static per language, all in this file.
struct NotchMascotFormStrings {
    let title: String
    let hint: String
    let none: String
    let golden: String
    let goldenLightning: String
    let goldenFury: String
    let divine: String
    let replay: String
    let unlockedFormat: String

    func name(of form: NotchMascotForm?) -> String {
        switch form {
        case nil: return none
        case .golden: return golden
        case .goldenLightning: return goldenLightning
        case .goldenFury: return goldenFury
        case .divine: return divine
        }
    }

    func unlocked(_ name: String) -> String { String(format: unlockedFormat, name) }
}

extension FeatureStrings {
    static func notchMascotForms(_ language: AppLanguage) -> NotchMascotFormStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ru: return .ru
        case .tr: return .tr
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension NotchMascotFormStrings {
    static let enUS = NotchMascotFormStrings(
        title: "Transformations",
        hint: "They unlock at levels 20, 30, 40 and 50. Each one turns it a new colour and wraps it in an aura; it plays the whole transformation the moment one unlocks.",
        none: "None",
        golden: "Golden aura",
        goldenLightning: "Golden lightning",
        goldenFury: "Golden fury",
        divine: "Divine aura",
        replay: "Watch the transformation",
        unlockedFormat: "Transformation unlocked: %@")
    static let ptBR = NotchMascotFormStrings(
        title: "Transformações",
        hint: "Desbloqueiam nos níveis 20, 30, 40 e 50. Cada uma muda a cor dele e o envolve numa aura; a transformação completa toca assim que uma é desbloqueada.",
        none: "Nenhuma",
        golden: "Aura dourada",
        goldenLightning: "Raio dourado",
        goldenFury: "Fúria dourada",
        divine: "Aura divina",
        replay: "Ver a transformação",
        unlockedFormat: "Transformação desbloqueada: %@")
    static let es = NotchMascotFormStrings(
        title: "Transformaciones",
        hint: "Se desbloquean en los niveles 20, 30, 40 y 50. Cada una le cambia el color y lo envuelve en un aura; la transformación completa se ve en cuanto se desbloquea.",
        none: "Ninguna",
        golden: "Aura dorada",
        goldenLightning: "Rayo dorado",
        goldenFury: "Furia dorada",
        divine: "Aura divina",
        replay: "Ver la transformación",
        unlockedFormat: "Transformación desbloqueada: %@")
    static let sk = NotchMascotFormStrings(
        title: "Premeny",
        hint: "Odomykajú sa na úrovniach 20, 30, 40 a 50. Každá mu zmení farbu a obalí ho aurou; celá premena sa prehrá hneď, ako sa odomkne.",
        none: "Žiadna",
        golden: "Zlatá aura",
        goldenLightning: "Zlatý blesk",
        goldenFury: "Zlatá zúrivosť",
        divine: "Božská aura",
        replay: "Pozrieť premenu",
        unlockedFormat: "Odomknutá premena: %@")
    static let de = NotchMascotFormStrings(
        title: "Verwandlungen",
        hint: "Sie werden auf Stufe 20, 30, 40 und 50 freigeschaltet. Jede gibt ihm eine neue Farbe und hüllt es in eine Aura; sobald eine freigeschaltet wird, spielt die ganze Verwandlung.",
        none: "Keine",
        golden: "Goldene Aura",
        goldenLightning: "Goldener Blitz",
        goldenFury: "Goldene Wut",
        divine: "Göttliche Aura",
        replay: "Verwandlung ansehen",
        unlockedFormat: "Verwandlung freigeschaltet: %@")
    static let fr = NotchMascotFormStrings(
        title: "Transformations",
        hint: "Elles se débloquent aux niveaux 20, 30, 40 et 50. Chacune lui donne une nouvelle couleur et l’enveloppe d’une aura ; la transformation complète se joue dès qu’elle est débloquée.",
        none: "Aucune",
        golden: "Aura dorée",
        goldenLightning: "Éclair doré",
        goldenFury: "Fureur dorée",
        divine: "Aura divine",
        replay: "Voir la transformation",
        unlockedFormat: "Transformation débloquée : %@")
    static let it = NotchMascotFormStrings(
        title: "Trasformazioni",
        hint: "Si sbloccano ai livelli 20, 30, 40 e 50. Ognuna gli cambia colore e lo avvolge in un’aura; la trasformazione completa parte appena se ne sblocca una.",
        none: "Nessuna",
        golden: "Aura dorata",
        goldenLightning: "Fulmine dorato",
        goldenFury: "Furia dorata",
        divine: "Aura divina",
        replay: "Guarda la trasformazione",
        unlockedFormat: "Trasformazione sbloccata: %@")
    static let ru = NotchMascotFormStrings(
        title: "Превращения",
        hint: "Открываются на уровнях 20, 30, 40 и 50. Каждое меняет его цвет и окутывает аурой; полное превращение проигрывается сразу, как только оно открыто.",
        none: "Нет",
        golden: "Золотая аура",
        goldenLightning: "Золотая молния",
        goldenFury: "Золотая ярость",
        divine: "Божественная аура",
        replay: "Посмотреть превращение",
        unlockedFormat: "Открыто превращение: %@")
    static let tr = NotchMascotFormStrings(
        title: "Dönüşümler",
        hint: "20, 30, 40 ve 50. seviyelerde açılır. Her biri rengini değiştirir ve onu bir aurayla sarar; biri açıldığı anda dönüşümün tamamı oynatılır.",
        none: "Yok",
        golden: "Altın aura",
        goldenLightning: "Altın şimşek",
        goldenFury: "Altın öfke",
        divine: "İlahi aura",
        replay: "Dönüşümü izle",
        unlockedFormat: "Dönüşüm açıldı: %@")
    static let ja = NotchMascotFormStrings(
        title: "変身",
        hint: "レベル20、30、40、50で解放されます。それぞれ色が変わり、オーラをまといます。解放された瞬間に変身の全演出が流れます。",
        none: "なし",
        golden: "黄金のオーラ",
        goldenLightning: "黄金の稲妻",
        goldenFury: "黄金の怒り",
        divine: "神のオーラ",
        replay: "変身を見る",
        unlockedFormat: "変身が解放されました：%@")
    static let ko = NotchMascotFormStrings(
        title: "변신",
        hint: "레벨 20, 30, 40, 50에서 해제됩니다. 변신할 때마다 색이 바뀌고 오라를 두르며, 해제되는 순간 변신 장면 전체가 재생됩니다.",
        none: "없음",
        golden: "황금 오라",
        goldenLightning: "황금 번개",
        goldenFury: "황금 분노",
        divine: "신성한 오라",
        replay: "변신 보기",
        unlockedFormat: "변신 해제: %@")
    static let zhHans = NotchMascotFormStrings(
        title: "变身",
        hint: "在 20、30、40 和 50 级解锁。每次变身都会改变它的颜色并让它笼罩在光环中；解锁的那一刻会播放完整的变身动画。",
        none: "无",
        golden: "金色光环",
        goldenLightning: "金色闪电",
        goldenFury: "金色怒火",
        divine: "神圣光环",
        replay: "观看变身",
        unlockedFormat: "已解锁变身：%@")
    static let zhTW = NotchMascotFormStrings(
        title: "變身",
        hint: "在 20、30、40 和 50 級解鎖。每次變身都會改變牠的顏色並讓牠籠罩在光環中；解鎖的那一刻會播放完整的變身動畫。",
        none: "無",
        golden: "金色光環",
        goldenLightning: "金色閃電",
        goldenFury: "金色怒火",
        divine: "神聖光環",
        replay: "觀看變身",
        unlockedFormat: "已解鎖變身：%@")
    static let zhHK = NotchMascotFormStrings(
        title: "變身",
        hint: "在 20、30、40 和 50 級解鎖。每次變身都會改變牠的顏色並讓牠籠罩在光環中；解鎖的那一刻會播放完整的變身動畫。",
        none: "無",
        golden: "金色光環",
        goldenLightning: "金色閃電",
        goldenFury: "金色怒火",
        divine: "神聖光環",
        replay: "觀看變身",
        unlockedFormat: "已解鎖變身：%@")
    static let uk = NotchMascotFormStrings(
        title: "Перетворення",
        hint: "Відкриваються на рівнях 20, 30, 40 і 50. Кожне змінює його колір і огортає аурою; щойно перетворення відкривається, воно програється повністю.",
        none: "Немає",
        golden: "Золота аура",
        goldenLightning: "Золота блискавка",
        goldenFury: "Золота лють",
        divine: "Божественна аура",
        replay: "Переглянути перетворення",
        unlockedFormat: "Відкрито перетворення: %@")
}
