// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The GFX maximum clock section of Settings > GPU control (plan 7.1,
/// phase 4). MHz is written as each language's table already writes it.
struct GPUControlClockStrings {
    /// The section's header, and the slider's, field's and stepper's
    /// VoiceOver label.
    let section: String
    let toggle: String
    /// %d = the stock maximum in MHz.
    let stockFormat: String
    let footer: String
    let notePowerHeld: String
    /// Under the power control while only a clock is held.
    let noteClockHeld: String
    let switching: String
    /// %d = the floor, %d = the stock maximum, both in MHz.
    let outOfRangeFormat: String

    var all: [String] { [section, toggle, stockFormat, footer, notePowerHeld, noteClockHeld, switching, outOfRangeFormat] }
}

extension FeatureStrings {
    static func gpuControlClock(_ language: AppLanguage) -> GPUControlClockStrings {
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
        case .zhTW, .zhHK: return .zhTW
        case .uk: return .uk
        }
    }
}

extension GPUControlClockStrings {
    static let enUS = GPUControlClockStrings(
        section: "GFX maximum clock",
        toggle: "Lower the maximum clock",
        stockFormat: "Stock (%d MHz)",
        footer: "Only lower than stock; the kext checks every request. Nothing was measured below 200 W: a clock that gives less than 200 W is untested.",
        notePowerHeld: "A power limit is held. Choosing a clock first returns the power limit to its start-up value: the kext never holds both.",
        noteClockHeld: "A clock setting is held. Choosing a power limit first returns the clock to stock: the kext never holds both.",
        switching: "Returning the power limit to its start-up value first…",
        outOfRangeFormat: "Choose a value from %d to %d MHz.")

    static let es = GPUControlClockStrings(
        section: "Reloj máximo de GFX",
        toggle: "Bajar el reloj máximo",
        stockFormat: "De fábrica (%d MHz)",
        footer: "Solo por debajo del de fábrica; el kext revisa cada pedido. No se midió nada por debajo de 200 W: un reloj que dé menos de 200 W no está probado.",
        notePowerHeld: "Hay un límite de potencia puesto. Al elegir un reloj, primero el límite vuelve a su valor de arranque: el kext nunca mantiene las dos cosas.",
        noteClockHeld: "Hay un reloj máximo puesto. Al elegir un límite de potencia, primero el reloj vuelve a los valores de fábrica: el kext nunca mantiene las dos cosas.",
        switching: "Primero el límite de potencia vuelve a su valor de arranque…",
        outOfRangeFormat: "Elige un valor entre %d y %d MHz.")

    static let ptBR = GPUControlClockStrings(
        section: "Clock máximo da GFX",
        toggle: "Reduzir o clock máximo",
        stockFormat: "Padrão (%d MHz)",
        footer: "Só abaixo do padrão; o kext verifica cada pedido. Nada foi medido abaixo de 200 W: um clock que dê menos de 200 W não foi testado.",
        notePowerHeld: "Há um limite de energia mantido. Ao escolher um clock, primeiro o limite volta ao valor de inicialização: o kext nunca mantém os dois.",
        noteClockHeld: "Há um clock máximo mantido. Ao escolher um limite de energia, primeiro o clock volta ao padrão: o kext nunca mantém os dois.",
        switching: "Primeiro o limite de energia volta ao valor de inicialização…",
        outOfRangeFormat: "Escolha um valor entre %d e %d MHz.")

    static let tr = GPUControlClockStrings(
        section: "Maks. GFX saati",
        toggle: "Maks. saati düşür",
        stockFormat: "Fabrika (%d MHz)",
        footer: "Yalnızca fabrika değerinin altında; kext her isteği denetler. 200 W'ın altında hiçbir şey ölçülmedi: 200 W'tan az veren bir saat denenmedi.",
        notePowerHeld: "Bir güç sınırı tutuluyor. Saat seçmek önce güç sınırını başlangıç değerine döndürür: kext ikisini birlikte tutmaz.",
        noteClockHeld: "Bir maks. saat tutuluyor. Güç sınırı seçmek önce saati fabrika değerine döndürür: kext ikisini birlikte tutmaz.",
        switching: "Önce güç sınırı başlangıç değerine dönüyor…",
        outOfRangeFormat: "%d ile %d MHz arasında bir değer seçin.")

    static let ru = GPUControlClockStrings(
        section: "Макс. частота GFX",
        toggle: "Снизить максимальную частоту",
        stockFormat: "Заводская (%d МГц)",
        footer: "Только ниже заводской; kext проверяет каждый запрос. Ниже 200 Вт ничего не измерялось: частота, дающая меньше 200 Вт, не проверена.",
        notePowerHeld: "Удерживается лимит мощности. Выбор частоты сначала вернёт лимит к значению загрузки: kext никогда не удерживает оба.",
        noteClockHeld: "Удерживается макс. частота. Выбор лимита мощности сначала вернёт частоту к заводской: kext никогда не удерживает оба.",
        switching: "Сначала лимит мощности возвращается к значению загрузки…",
        outOfRangeFormat: "Выберите значение от %d до %d МГц.")

    static let sk = GPUControlClockStrings(
        section: "Maximálny takt GFX",
        toggle: "Znížiť maximálny takt",
        stockFormat: "Továrenský (%d MHz)",
        footer: "Iba pod továrenskú hodnotu; kext kontroluje každú požiadavku. Pod 200 W sa nič nemeralo: takt, ktorý dáva menej než 200 W, nie je overený.",
        notePowerHeld: "Drží sa limit príkonu. Výber taktu najprv vráti limit na štartovaciu hodnotu: kext nikdy nedrží oboje.",
        noteClockHeld: "Drží sa maximálny takt. Výber limitu príkonu najprv vráti takt na továrenskú hodnotu: kext nikdy nedrží oboje.",
        switching: "Najprv sa limit príkonu vracia na štartovaciu hodnotu…",
        outOfRangeFormat: "Vyberte hodnotu od %d do %d MHz.")

    static let de = GPUControlClockStrings(
        section: "Maximaler GFX-Takt",
        toggle: "Maximalen Takt senken",
        stockFormat: "Werkswert (%d MHz)",
        footer: "Nur unter den Werkswert; der Kext prüft jede Anfrage. Unter 200 W wurde nichts gemessen: Ein Takt, der weniger als 200 W ergibt, ist nicht erprobt.",
        notePowerHeld: "Ein Leistungslimit wird gehalten. Beim Wählen eines Takts geht das Limit zuerst auf seinen Startwert zurück: Der Kext hält nie beides.",
        noteClockHeld: "Ein maximaler Takt wird gehalten. Beim Wählen eines Leistungslimits geht der Takt zuerst auf den Werkswert zurück: Der Kext hält nie beides.",
        switching: "Das Leistungslimit geht zuerst auf seinen Startwert zurück…",
        outOfRangeFormat: "Wählen Sie einen Wert von %d bis %d MHz.")

    static let fr = GPUControlClockStrings(
        section: "Fréquence GFX maximale",
        toggle: "Abaisser la fréquence maximale",
        stockFormat: "Usine (%d MHz)",
        footer: "Seulement sous la valeur d’usine ; le kext vérifie chaque demande. Rien n’a été mesuré sous 200 W : une fréquence qui donne moins de 200 W n’est pas testée.",
        notePowerHeld: "Une limite de puissance est maintenue. Choisir une fréquence remet d’abord la limite à sa valeur de démarrage : le kext ne maintient jamais les deux.",
        noteClockHeld: "Une fréquence maximale est maintenue. Choisir une limite de puissance remet d’abord la fréquence à sa valeur d’usine : le kext ne maintient jamais les deux.",
        switching: "La limite de puissance revient d’abord à sa valeur de démarrage…",
        outOfRangeFormat: "Choisissez une valeur de %d à %d MHz.")

    static let it = GPUControlClockStrings(
        section: "Clock GFX massimo",
        toggle: "Abbassa il clock massimo",
        stockFormat: "Di fabbrica (%d MHz)",
        footer: "Solo sotto il valore di fabbrica; il kext controlla ogni richiesta. Sotto i 200 W non è stato misurato nulla: un clock che dà meno di 200 W non è provato.",
        notePowerHeld: "È mantenuto un limite di potenza. Scegliendo un clock, prima il limite torna al valore di avvio: il kext non mantiene mai entrambi.",
        noteClockHeld: "È mantenuto un clock massimo. Scegliendo un limite di potenza, prima il clock torna al valore di fabbrica: il kext non mantiene mai entrambi.",
        switching: "Prima il limite di potenza torna al valore di avvio…",
        outOfRangeFormat: "Scegli un valore tra %d e %d MHz.")

    static let ja = GPUControlClockStrings(
        section: "GFX 最大クロック",
        toggle: "最大クロックを下げる",
        stockFormat: "純正 (%d MHz)",
        footer: "純正より低い値のみです。kext はすべての要求を確認します。200 W 未満は何も測定していません: 200 W 未満になるクロックは未検証です。",
        notePowerHeld: "電力制限が保持されています。クロックを選ぶと、先に電力制限が起動時の値に戻ります。kext は両方を同時に保持しません。",
        noteClockHeld: "最大クロックが保持されています。電力制限を選ぶと、先にクロックが純正に戻ります。kext は両方を同時に保持しません。",
        switching: "先に電力制限を起動時の値に戻しています…",
        outOfRangeFormat: "%d から %d MHz の値を選んでください。")

    static let ko = GPUControlClockStrings(
        section: "최대 GFX 클록",
        toggle: "최대 클록 낮추기",
        stockFormat: "기본값 (%d MHz)",
        footer: "기본값보다 낮게만 설정할 수 있으며, kext가 모든 요청을 확인합니다. 200 W 미만은 측정하지 않았습니다: 200 W 미만이 되는 클록은 검증되지 않았습니다.",
        notePowerHeld: "전력 한도가 유지되고 있습니다. 클록을 선택하면 먼저 전력 한도가 시동 값으로 돌아갑니다. kext는 둘을 함께 유지하지 않습니다.",
        noteClockHeld: "최대 클록이 유지되고 있습니다. 전력 한도를 선택하면 먼저 클록이 기본값으로 돌아갑니다. kext는 둘을 함께 유지하지 않습니다.",
        switching: "먼저 전력 한도를 시동 값으로 돌리는 중…",
        outOfRangeFormat: "%d에서 %d MHz 사이의 값을 선택하십시오.")

    static let zhHans = GPUControlClockStrings(
        section: "GFX 最大时钟",
        toggle: "降低最大时钟",
        stockFormat: "出厂值（%d MHz）",
        footer: "只能低于出厂值；kext 会检查每个请求。低于 200 W 时没有任何测量：使功率低于 200 W 的时钟未经测试。",
        notePowerHeld: "当前设有功率上限。选择时钟会先使功率上限返回启动值：kext 绝不会同时维持两者。",
        noteClockHeld: "正在维持最大时钟。选择功率上限会先使时钟返回出厂值：kext 绝不会同时维持两者。",
        switching: "正在先使功率上限返回启动值…",
        outOfRangeFormat: "请选择 %d 到 %d MHz 之间的值。")

    static let zhTW = GPUControlClockStrings(
        section: "GFX 最大時脈",
        toggle: "降低最大時脈",
        stockFormat: "原廠值（%d MHz）",
        footer: "只能低於原廠值；kext 會檢查每個要求。低於 200 W 時沒有任何量測：使功率低於 200 W 的時脈未經測試。",
        notePowerHeld: "目前設有功率上限。選擇時脈會先使功率上限回到啟動值：kext 絕不會同時維持兩者。",
        noteClockHeld: "正在維持最大時脈。選擇功率上限會先使時脈回到原廠值：kext 絕不會同時維持兩者。",
        switching: "正在先使功率上限回到啟動值…",
        outOfRangeFormat: "請選擇 %d 到 %d MHz 之間的值。")

    static let uk = GPUControlClockStrings(
        section: "Макс. частота GFX",
        toggle: "Знизити максимальну частоту",
        stockFormat: "Заводська (%d МГц)",
        footer: "Лише нижче заводської; kext перевіряє кожен запит. Нижче 200 Вт нічого не вимірювали: частота, що дає менше 200 Вт, не перевірена.",
        notePowerHeld: "Утримується ліміт потужності. Вибір частоти спершу поверне ліміт до значення завантаження: kext ніколи не утримує обидва.",
        noteClockHeld: "Утримується макс. частота. Вибір ліміту потужності спершу поверне частоту до заводської: kext ніколи не утримує обидва.",
        switching: "Спершу ліміт потужності повертається до значення завантаження…",
        outOfRangeFormat: "Виберіть значення від %d до %d МГц.")
}
