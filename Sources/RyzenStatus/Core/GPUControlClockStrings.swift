// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The GFX maximum clock section of Settings > GPU control (plan 7.1,
/// phase 4). MHz is written as each language's table already writes it.
struct GPUControlClockStrings {
    /// The section's header, and the slider's VoiceOver label.
    let section: String
    /// VoiceOver: the MHz field.
    let fieldLabel: String
    /// VoiceOver: the stepper; %d = its step in MHz.
    let stepperFormat: String
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
    /// The slider's VoiceOver help (a11y A6, A16): %1$d = the floor,
    /// %2$d = the stock maximum, both in MHz.
    let sliderHelpFormat: String

    // The GFX minimum clock section (GPUSensors 0.9.0). Its stock caption,
    // range note, power note and wait reuse the texts above.
    /// The section's header, and the slider's VoiceOver label.
    let minSection: String
    /// VoiceOver: the MHz field.
    let minFieldLabel: String
    /// VoiceOver: the stepper; %d = its step in MHz.
    let minStepperFormat: String
    let minToggle: String
    let minFooter: String
    /// The slider's VoiceOver help: %1$d = the stock minimum, %2$d = the top
    /// (the GFX maximum in force), both in MHz.
    let minSliderHelpFormat: String

    var all: [String] {
        [section, toggle, stockFormat, footer, notePowerHeld, noteClockHeld, switching, outOfRangeFormat,
         fieldLabel, stepperFormat, sliderHelpFormat,
         minSection, minFieldLabel, minStepperFormat, minToggle, minFooter, minSliderHelpFormat]
    }
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
        fieldLabel: "GFX maximum clock in MHz",
        stepperFormat: "GFX maximum clock, steps of %d MHz",
        toggle: "Lower the maximum clock",
        stockFormat: "Stock (%d MHz)",
        footer: "Only lower than stock; the kext checks every request.",
        notePowerHeld: "A power limit is held. Choosing a clock first returns the power limit to its start-up value: the kext never holds both.",
        noteClockHeld: "A clock setting is held. Choosing a power limit first returns the clock to stock: the kext never holds both.",
        switching: "Returning the power limit to its start-up value first…",
        outOfRangeFormat: "Choose a value from %d to %d MHz.",
        sliderHelpFormat: "From %1$d MHz to the stock maximum, %2$d MHz. Only lowers the maximum; the value is sent when you stop moving it.",
        minSection: "GFX minimum clock",
        minFieldLabel: "GFX minimum clock in MHz",
        minStepperFormat: "GFX minimum clock, steps of %d MHz",
        minToggle: "Raise the minimum clock",
        minFooter: "Only higher than stock and never above the GFX maximum; the kext checks every request. A higher minimum keeps the clock up at idle, so the card draws more power and runs warmer; the kext goes back to stock if the GPU gets too hot.",
        minSliderHelpFormat: "From the stock minimum, %1$d MHz, to %2$d MHz. Only raises the minimum; the value is sent when you stop moving it.")

    static let es = GPUControlClockStrings(
        section: "Reloj máximo de GFX",
        fieldLabel: "Reloj máximo de GFX en MHz",
        stepperFormat: "Reloj máximo de GFX, pasos de %d MHz",
        toggle: "Bajar el reloj máximo",
        stockFormat: "De fábrica (%d MHz)",
        footer: "Solo por debajo del de fábrica; el kext revisa cada pedido.",
        notePowerHeld: "Hay un límite de potencia puesto. Al elegir un reloj, primero el límite vuelve a su valor de arranque: el kext nunca mantiene las dos cosas.",
        noteClockHeld: "Hay un reloj máximo puesto. Al elegir un límite de potencia, primero el reloj vuelve a los valores de fábrica: el kext nunca mantiene las dos cosas.",
        switching: "Primero el límite de potencia vuelve a su valor de arranque…",
        outOfRangeFormat: "Elige un valor entre %d y %d MHz.",
        sliderHelpFormat: "De %1$d MHz al máximo de fábrica, %2$d MHz. Solo baja el máximo; el valor se manda cuando dejas de moverlo.",
        minSection: "Reloj mínimo de GFX",
        minFieldLabel: "Reloj mínimo de GFX en MHz",
        minStepperFormat: "Reloj mínimo de GFX, pasos de %d MHz",
        minToggle: "Subir el reloj mínimo",
        minFooter: "Solo por encima del de fábrica y nunca sobre el máximo de GFX; el kext revisa cada pedido. Un mínimo más alto mantiene el reloj arriba en reposo, así que la tarjeta consume más y se calienta más; el kext vuelve a los valores de fábrica si la GPU se calienta demasiado.",
        minSliderHelpFormat: "Del mínimo de fábrica, %1$d MHz, a %2$d MHz. Solo sube el mínimo; el valor se manda cuando dejas de moverlo.")

    static let ptBR = GPUControlClockStrings(
        section: "Clock máximo da GFX",
        fieldLabel: "Clock máximo da GFX em MHz",
        stepperFormat: "Clock máximo da GFX, passos de %d MHz",
        toggle: "Reduzir o clock máximo",
        stockFormat: "Padrão (%d MHz)",
        footer: "Só abaixo do padrão; o kext verifica cada pedido.",
        notePowerHeld: "Há um limite de energia mantido. Ao escolher um clock, primeiro o limite volta ao valor de inicialização: o kext nunca mantém os dois.",
        noteClockHeld: "Há um clock máximo mantido. Ao escolher um limite de energia, primeiro o clock volta ao padrão: o kext nunca mantém os dois.",
        switching: "Primeiro o limite de energia volta ao valor de inicialização…",
        outOfRangeFormat: "Escolha um valor entre %d e %d MHz.",
        sliderHelpFormat: "De %1$d MHz até o máximo de fábrica, %2$d MHz. Só reduz o máximo; o valor é enviado quando você para de movê-lo.",
        minSection: "Clock mínimo da GFX",
        minFieldLabel: "Clock mínimo da GFX em MHz",
        minStepperFormat: "Clock mínimo da GFX, passos de %d MHz",
        minToggle: "Aumentar o clock mínimo",
        minFooter: "Só acima do padrão e nunca acima do máximo da GFX; o kext verifica cada pedido. Um mínimo mais alto mantém o clock alto em repouso, então a placa consome mais e esquenta mais; o kext volta ao padrão se a GPU esquentar demais.",
        minSliderHelpFormat: "Do mínimo de fábrica, %1$d MHz, até %2$d MHz. Só aumenta o mínimo; o valor é enviado quando você para de movê-lo.")

    static let tr = GPUControlClockStrings(
        section: "Maks. GFX saat hızı",
        fieldLabel: "Maks. GFX saat hızı (MHz)",
        stepperFormat: "Maks. GFX saat hızı, %d MHz'lik adımlar",
        toggle: "Maks. saat hızını düşür",
        stockFormat: "Fabrika (%d MHz)",
        footer: "Yalnızca fabrika değerinin altında; kext her isteği denetler.",
        notePowerHeld: "Bir güç sınırı tutuluyor. Saat hızı seçmek önce güç sınırını başlangıç değerine döndürür: kext ikisini birlikte tutmaz.",
        noteClockHeld: "Bir maks. saat hızı tutuluyor. Güç sınırı seçmek önce saat hızını fabrika değerine döndürür: kext ikisini birlikte tutmaz.",
        switching: "Önce güç sınırı başlangıç değerine dönüyor…",
        outOfRangeFormat: "%d ile %d MHz arasında bir değer seçin.",
        sliderHelpFormat: "%1$d MHz'den fabrika maksimumu %2$d MHz'e kadar. Yalnızca maksimumu düşürür; değer, hareket ettirmeyi bıraktığınızda gönderilir.",
        minSection: "Min. GFX saat hızı",
        minFieldLabel: "Min. GFX saat hızı (MHz)",
        minStepperFormat: "Min. GFX saat hızı, %d MHz'lik adımlar",
        minToggle: "Min. saat hızını yükselt",
        minFooter: "Yalnızca fabrika değerinin üstünde ve asla maks. GFX saat hızının üstünde değil; kext her isteği denetler. Daha yüksek bir minimum, saat hızını boştayken de yüksek tutar; kart daha çok güç çeker ve daha çok ısınır. GPU fazla ısınırsa kext fabrika değerine döner.",
        minSliderHelpFormat: "Fabrika minimumu %1$d MHz'den %2$d MHz'e kadar. Yalnızca minimumu yükseltir; değer, hareket ettirmeyi bıraktığınızda gönderilir.")

    static let ru = GPUControlClockStrings(
        section: "Макс. частота GFX",
        fieldLabel: "Макс. частота GFX в МГц",
        stepperFormat: "Макс. частота GFX, шаг %d МГц",
        toggle: "Снизить максимальную частоту",
        stockFormat: "Заводская (%d МГц)",
        footer: "Только ниже заводской; kext проверяет каждый запрос.",
        notePowerHeld: "Удерживается лимит мощности. Выбор частоты сначала вернёт лимит к значению загрузки: kext никогда не удерживает оба.",
        noteClockHeld: "Удерживается макс. частота. Выбор лимита мощности сначала вернёт частоту к заводской: kext никогда не удерживает оба.",
        switching: "Сначала лимит мощности возвращается к значению загрузки…",
        outOfRangeFormat: "Выберите значение от %d до %d МГц.",
        sliderHelpFormat: "От %1$d МГц до заводского максимума, %2$d МГц. Только снижает максимум; значение отправляется, когда вы перестаёте его двигать.",
        minSection: "Мин. частота GFX",
        minFieldLabel: "Мин. частота GFX в МГц",
        minStepperFormat: "Мин. частота GFX, шаг %d МГц",
        minToggle: "Повысить минимальную частоту",
        minFooter: "Только выше заводской и никогда не выше макс. частоты GFX; kext проверяет каждый запрос. Более высокий минимум держит частоту поднятой в простое, поэтому карта потребляет больше и сильнее греется; kext возвращает заводские значения, если GPU перегревается.",
        minSliderHelpFormat: "От заводского минимума, %1$d МГц, до %2$d МГц. Только повышает минимум; значение отправляется, когда вы перестаёте его двигать.")

    static let sk = GPUControlClockStrings(
        section: "Maximálny takt GFX",
        fieldLabel: "Maximálny takt GFX v MHz",
        stepperFormat: "Maximálny takt GFX, kroky po %d MHz",
        toggle: "Znížiť maximálny takt",
        stockFormat: "Továrenský (%d MHz)",
        footer: "Iba pod továrenskú hodnotu; kext kontroluje každú požiadavku.",
        notePowerHeld: "Drží sa limit príkonu. Výber taktu najprv vráti limit na štartovaciu hodnotu: kext nikdy nedrží oboje.",
        noteClockHeld: "Drží sa maximálny takt. Výber limitu príkonu najprv vráti takt na továrenskú hodnotu: kext nikdy nedrží oboje.",
        switching: "Najprv sa limit príkonu vracia na štartovaciu hodnotu…",
        outOfRangeFormat: "Vyberte hodnotu od %d do %d MHz.",
        sliderHelpFormat: "Od %1$d MHz po továrenské maximum, %2$d MHz. Maximum iba znižuje; hodnota sa odošle, keď ním prestanete hýbať.",
        minSection: "Minimálny takt GFX",
        minFieldLabel: "Minimálny takt GFX v MHz",
        minStepperFormat: "Minimálny takt GFX, kroky po %d MHz",
        minToggle: "Zvýšiť minimálny takt",
        minFooter: "Iba nad továrenskú hodnotu a nikdy nad maximálny takt GFX; kext kontroluje každú požiadavku. Vyššie minimum drží takt hore aj v nečinnosti, takže karta viac berie a viac sa zahrieva; ak sa GPU príliš zahreje, kext vráti továrenské hodnoty.",
        minSliderHelpFormat: "Od továrenského minima, %1$d MHz, po %2$d MHz. Minimum iba zvyšuje; hodnota sa odošle, keď ním prestanete hýbať.")

    static let de = GPUControlClockStrings(
        section: "Maximaler GFX-Takt",
        fieldLabel: "Maximaler GFX-Takt in MHz",
        stepperFormat: "Maximaler GFX-Takt, Schritte von %d MHz",
        toggle: "Maximalen Takt senken",
        stockFormat: "Werkswert (%d MHz)",
        footer: "Nur unter den Werkswert; der Kext prüft jede Anfrage.",
        notePowerHeld: "Ein Leistungslimit wird gehalten. Beim Wählen eines Takts geht das Limit zuerst auf seinen Startwert zurück: Der Kext hält nie beides.",
        noteClockHeld: "Ein maximaler Takt wird gehalten. Beim Wählen eines Leistungslimits geht der Takt zuerst auf den Werkswert zurück: Der Kext hält nie beides.",
        switching: "Das Leistungslimit geht zuerst auf seinen Startwert zurück…",
        outOfRangeFormat: "Wählen Sie einen Wert von %d bis %d MHz.",
        sliderHelpFormat: "Von %1$d MHz bis zum Werksmaximum, %2$d MHz. Senkt nur das Maximum; der Wert wird gesendet, wenn Sie ihn nicht mehr bewegen.",
        minSection: "Minimaler GFX-Takt",
        minFieldLabel: "Minimaler GFX-Takt in MHz",
        minStepperFormat: "Minimaler GFX-Takt, Schritte von %d MHz",
        minToggle: "Minimalen Takt anheben",
        minFooter: "Nur über den Werkswert und nie über den maximalen GFX-Takt; der Kext prüft jede Anfrage. Ein höheres Minimum hält den Takt auch im Leerlauf oben, die Karte braucht also mehr Strom und wird wärmer; wird die GPU zu heiß, geht der Kext auf die Werkswerte zurück.",
        minSliderHelpFormat: "Vom Werksminimum, %1$d MHz, bis %2$d MHz. Hebt nur das Minimum an; der Wert wird gesendet, wenn Sie ihn nicht mehr bewegen.")

    static let fr = GPUControlClockStrings(
        section: "Fréquence GFX maximale",
        fieldLabel: "Fréquence GFX maximale en MHz",
        stepperFormat: "Fréquence GFX maximale, pas de %d MHz",
        toggle: "Abaisser la fréquence maximale",
        stockFormat: "Usine (%d MHz)",
        footer: "Seulement sous la valeur d’usine ; le kext vérifie chaque demande.",
        notePowerHeld: "Une limite de puissance est maintenue. Choisir une fréquence remet d’abord la limite à sa valeur de démarrage : le kext ne maintient jamais les deux.",
        noteClockHeld: "Une fréquence maximale est maintenue. Choisir une limite de puissance remet d’abord la fréquence à sa valeur d’usine : le kext ne maintient jamais les deux.",
        switching: "La limite de puissance revient d’abord à sa valeur de démarrage…",
        outOfRangeFormat: "Choisissez une valeur de %d à %d MHz.",
        sliderHelpFormat: "De %1$d MHz au maximum d’usine, %2$d MHz. Abaisse seulement le maximum ; la valeur est envoyée quand vous arrêtez de la déplacer.",
        minSection: "Fréquence GFX minimale",
        minFieldLabel: "Fréquence GFX minimale en MHz",
        minStepperFormat: "Fréquence GFX minimale, pas de %d MHz",
        minToggle: "Relever la fréquence minimale",
        minFooter: "Seulement au-dessus de la valeur d’usine et jamais au-dessus de la fréquence GFX maximale ; le kext vérifie chaque demande. Un minimum plus haut garde la fréquence haute au repos : la carte consomme et chauffe davantage ; le kext revient aux valeurs d’usine si le GPU chauffe trop.",
        minSliderHelpFormat: "Du minimum d’usine, %1$d MHz, à %2$d MHz. Relève seulement le minimum ; la valeur est envoyée quand vous arrêtez de la déplacer.")

    static let it = GPUControlClockStrings(
        section: "Clock GFX massimo",
        fieldLabel: "Clock GFX massimo in MHz",
        stepperFormat: "Clock GFX massimo, passi da %d MHz",
        toggle: "Abbassa il clock massimo",
        stockFormat: "Di fabbrica (%d MHz)",
        footer: "Solo sotto il valore di fabbrica; il kext controlla ogni richiesta.",
        notePowerHeld: "È mantenuto un limite di potenza. Scegliendo un clock, prima il limite torna al valore di avvio: il kext non mantiene mai entrambi.",
        noteClockHeld: "È mantenuto un clock massimo. Scegliendo un limite di potenza, prima il clock torna al valore di fabbrica: il kext non mantiene mai entrambi.",
        switching: "Prima il limite di potenza torna al valore di avvio…",
        outOfRangeFormat: "Scegli un valore tra %d e %d MHz.",
        sliderHelpFormat: "Da %1$d MHz al massimo di fabbrica, %2$d MHz. Abbassa solo il massimo; il valore viene inviato quando smetti di muoverlo.",
        minSection: "Clock GFX minimo",
        minFieldLabel: "Clock GFX minimo in MHz",
        minStepperFormat: "Clock GFX minimo, passi da %d MHz",
        minToggle: "Alza il clock minimo",
        minFooter: "Solo sopra il valore di fabbrica e mai sopra il clock GFX massimo; il kext controlla ogni richiesta. Un minimo più alto tiene il clock alto anche a riposo, quindi la scheda consuma e scalda di più; il kext torna ai valori di fabbrica se la GPU scalda troppo.",
        minSliderHelpFormat: "Dal minimo di fabbrica, %1$d MHz, a %2$d MHz. Alza solo il minimo; il valore viene inviato quando smetti di muoverlo.")

    static let ja = GPUControlClockStrings(
        section: "GFX 最大クロック",
        fieldLabel: "GFX 最大クロック（MHz）",
        stepperFormat: "GFX 最大クロック、%d MHz 刻み",
        toggle: "最大クロックを下げる",
        stockFormat: "純正 (%d MHz)",
        footer: "純正より低い値のみです。kext はすべての要求を確認します。",
        notePowerHeld: "電力制限が保持されています。クロックを選ぶと、先に電力制限が起動時の値に戻ります。kext は両方を同時に保持しません。",
        noteClockHeld: "最大クロックが保持されています。電力制限を選ぶと、先にクロックが純正に戻ります。kext は両方を同時に保持しません。",
        switching: "先に電力制限を起動時の値に戻しています…",
        outOfRangeFormat: "%d から %d MHz の値を選んでください。",
        sliderHelpFormat: "%1$d MHz から純正の最大値 %2$d MHz まで。最大値を下げるだけです。動かすのをやめると値が送られます。",
        minSection: "GFX 最小クロック",
        minFieldLabel: "GFX 最小クロック（MHz）",
        minStepperFormat: "GFX 最小クロック、%d MHz 刻み",
        minToggle: "最小クロックを上げる",
        minFooter: "純正より高く、GFX 最大クロック以下の値のみです。kext はすべての要求を確認します。最小値を上げるとアイドル時もクロックが高いままになり、消費電力と温度が上がります。GPU が熱くなりすぎると kext は純正に戻します。",
        minSliderHelpFormat: "純正の最小値 %1$d MHz から %2$d MHz まで。最小値を上げるだけです。動かすのをやめると値が送られます。")

    static let ko = GPUControlClockStrings(
        section: "최대 GFX 클록",
        fieldLabel: "최대 GFX 클록(MHz)",
        stepperFormat: "최대 GFX 클록, %d MHz 단위",
        toggle: "최대 클록 낮추기",
        stockFormat: "기본값 (%d MHz)",
        footer: "기본값보다 낮게만 설정할 수 있으며, kext가 모든 요청을 확인합니다.",
        notePowerHeld: "전력 한도가 유지되고 있습니다. 클록을 선택하면 먼저 전력 한도가 시동 값으로 돌아갑니다. kext는 둘을 함께 유지하지 않습니다.",
        noteClockHeld: "최대 클록이 유지되고 있습니다. 전력 한도를 선택하면 먼저 클록이 기본값으로 돌아갑니다. kext는 둘을 함께 유지하지 않습니다.",
        switching: "먼저 전력 한도를 시동 값으로 돌리는 중…",
        outOfRangeFormat: "%d에서 %d MHz 사이의 값을 선택하십시오.",
        sliderHelpFormat: "%1$d MHz부터 기본 최대값 %2$d MHz까지. 최대값을 낮추기만 하며, 움직임을 멈추면 값이 전송됩니다.",
        minSection: "최소 GFX 클록",
        minFieldLabel: "최소 GFX 클록(MHz)",
        minStepperFormat: "최소 GFX 클록, %d MHz 단위",
        minToggle: "최소 클록 높이기",
        minFooter: "기본값보다 높게, 최대 GFX 클록을 넘지 않게만 설정할 수 있으며, kext가 모든 요청을 확인합니다. 최소값을 높이면 유휴 상태에서도 클록이 높게 유지되어 전력 소모와 발열이 늘어납니다. GPU가 너무 뜨거워지면 kext가 기본값으로 되돌립니다.",
        minSliderHelpFormat: "기본 최소값 %1$d MHz부터 %2$d MHz까지. 최소값을 높이기만 하며, 움직임을 멈추면 값이 전송됩니다.")

    static let zhHans = GPUControlClockStrings(
        section: "GFX 最大时钟频率",
        fieldLabel: "GFX 最大时钟频率（MHz）",
        stepperFormat: "GFX 最大时钟频率，步长 %d MHz",
        toggle: "降低最大时钟频率",
        stockFormat: "出厂值（%d MHz）",
        footer: "只能低于出厂值；kext 会检查每个请求。",
        notePowerHeld: "当前设有功率上限。选择时钟频率会先使功率上限返回启动值：kext 绝不会同时维持两者。",
        noteClockHeld: "正在维持最大时钟频率。选择功率上限会先使时钟频率返回出厂值：kext 绝不会同时维持两者。",
        switching: "正在先使功率上限返回启动值…",
        outOfRangeFormat: "请选择 %d 到 %d MHz 之间的值。",
        sliderHelpFormat: "从 %1$d MHz 到出厂最大值 %2$d MHz。只会降低最大值；停止移动后发送该值。",
        minSection: "GFX 最小时钟频率",
        minFieldLabel: "GFX 最小时钟频率（MHz）",
        minStepperFormat: "GFX 最小时钟频率，步长 %d MHz",
        minToggle: "提高最小时钟频率",
        minFooter: "只能高于出厂值，且不超过 GFX 最大时钟频率；kext 会检查每个请求。提高最小值会让时钟在空闲时也保持较高，显卡功耗和温度都会上升；GPU 过热时 kext 会恢复出厂值。",
        minSliderHelpFormat: "从出厂最小值 %1$d MHz 到 %2$d MHz。只会提高最小值；停止移动后发送该值。")

    static let zhTW = GPUControlClockStrings(
        section: "GFX 最大時脈",
        fieldLabel: "GFX 最大時脈（MHz）",
        stepperFormat: "GFX 最大時脈，間距 %d MHz",
        toggle: "降低最大時脈",
        stockFormat: "原廠值（%d MHz）",
        footer: "只能低於原廠值；kext 會檢查每個要求。",
        notePowerHeld: "目前設有功率上限。選擇時脈會先使功率上限回到啟動值：kext 絕不會同時維持兩者。",
        noteClockHeld: "正在維持最大時脈。選擇功率上限會先使時脈回到原廠值：kext 絕不會同時維持兩者。",
        switching: "正在先使功率上限回到啟動值…",
        outOfRangeFormat: "請選擇 %d 到 %d MHz 之間的值。",
        sliderHelpFormat: "從 %1$d MHz 到原廠最大值 %2$d MHz。只會降低最大值；停止移動後傳送該值。",
        minSection: "GFX 最小時脈",
        minFieldLabel: "GFX 最小時脈（MHz）",
        minStepperFormat: "GFX 最小時脈，間距 %d MHz",
        minToggle: "提高最小時脈",
        minFooter: "只能高於原廠值，且不超過 GFX 最大時脈；kext 會檢查每個要求。提高最小值會讓時脈在閒置時也保持較高，顯示卡耗電與溫度都會上升；GPU 過熱時 kext 會恢復原廠值。",
        minSliderHelpFormat: "從原廠最小值 %1$d MHz 到 %2$d MHz。只會提高最小值；停止移動後傳送該值。")

    static let uk = GPUControlClockStrings(
        section: "Макс. частота GFX",
        fieldLabel: "Макс. частота GFX у МГц",
        stepperFormat: "Макс. частота GFX, крок %d МГц",
        toggle: "Знизити максимальну частоту",
        stockFormat: "Заводська (%d МГц)",
        footer: "Лише нижче заводської; kext перевіряє кожен запит.",
        notePowerHeld: "Утримується ліміт потужності. Вибір частоти спершу поверне ліміт до значення завантаження: kext ніколи не утримує обидва.",
        noteClockHeld: "Утримується макс. частота. Вибір ліміту потужності спершу поверне частоту до заводської: kext ніколи не утримує обидва.",
        switching: "Спершу ліміт потужності повертається до значення завантаження…",
        outOfRangeFormat: "Виберіть значення від %d до %d МГц.",
        sliderHelpFormat: "Від %1$d МГц до заводського максимуму, %2$d МГц. Лише знижує максимум; значення надсилається, коли ви перестаєте його рухати.",
        minSection: "Мін. частота GFX",
        minFieldLabel: "Мін. частота GFX у МГц",
        minStepperFormat: "Мін. частота GFX, крок %d МГц",
        minToggle: "Підвищити мінімальну частоту",
        minFooter: "Лише вище заводської і ніколи не вище макс. частоти GFX; kext перевіряє кожен запит. Вищий мінімум тримає частоту піднятою в простої, тож карта споживає більше й сильніше гріється; kext повертає заводські значення, якщо GPU перегрівається.",
        minSliderHelpFormat: "Від заводського мінімуму, %1$d МГц, до %2$d МГц. Лише підвищує мінімум; значення надсилається, коли ви перестаєте його рухати.")
}
