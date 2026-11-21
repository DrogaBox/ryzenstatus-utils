// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The fan section of Settings > GPU control: the curve editor and zero RPM
/// (plan 7.3, phase 3). `%%` is a literal percent in the format strings.
struct GPUControlFanStrings {
    let section: String
    let curveToggle: String
    let zeroRpmToggle: String
    /// %d = the point (1 to 5).
    let pointFormat: String
    /// VoiceOver: %d = the point.
    let pointTempFormat: String
    let pointSpeedFormat: String
    let stepTempFormat: String
    let stepSpeedFormat: String
    /// VoiceOver for the chart: %d = the 100 % temperature.
    let chartLabelFormat: String
    /// The chart's rule: %d = the 100 % temperature.
    let limitFormat: String
    let curveOK: String
    /// %d = the point, %@ = the rule.
    let curveFailFormat: String
    let ruleRange: String
    let ruleOrder: String
    let ruleFirst: String
    /// %d = the 100 % temperature.
    let ruleLastFormat: String
    let ruleCooling: String
    let apply: String
    /// The button when the draft gives the fan hold back: in this section's
    /// stock words, not the power section's start-up.
    let backToStock: String
    /// %d = the 100 % temperature.
    let footerFormat: String
    let notePowerHeld: String
    let noteCurveHeld: String
    let notChecked: String
    /// Under the chart: which line is which ("Charts": label the lines).
    let chartKey: String
    /// VoiceOver's hint on "Apply curve" (a11y A6).
    let applyHint: String
    /// The chart's VoiceOver value (a11y A12): %1$@ = the draft's points,
    /// %2$@ = the stock curve's, %3$@ = `limitFormat` filled in.
    let chartValueFormat: String
    /// The same without a stock curve: %1$@ = the draft's points, %2$@ = the limit.
    let chartValueDraftFormat: String
    /// Said when Escape gives the draft back (a11y A10).
    let draftDiscarded: String

    var all: [String] {
        [section, curveToggle, zeroRpmToggle, pointFormat, pointTempFormat, pointSpeedFormat, stepTempFormat,
         stepSpeedFormat, chartLabelFormat, limitFormat, curveOK, curveFailFormat, ruleRange, ruleOrder, ruleFirst,
         ruleLastFormat, ruleCooling, apply, backToStock, footerFormat, notePowerHeld, noteCurveHeld, notChecked,
         chartKey, applyHint, chartValueFormat, chartValueDraftFormat, draftDiscarded]
    }

    /// The rule a curve check names, nil for the checks that are not about a
    /// point (those use the grouped sentence, plan 13).
    func rule(_ check: GPUControlOD8Check, limitC: Int) -> String? {
        switch check {
        case .curveRange: return ruleRange
        case .curveOrder: return ruleOrder
        case .curveFirst: return ruleFirst
        case .curveLast: return String(format: ruleLastFormat, limitC)
        case .curveCooling: return ruleCooling
        default: return nil
        }
    }
}

extension FeatureStrings {
    static func gpuControlFan(_ language: AppLanguage) -> GPUControlFanStrings {
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

extension GPUControlFanStrings {
    static let enUS = GPUControlFanStrings(
        section: "Fan",
        curveToggle: "Custom curve",
        zeroRpmToggle: "Fan always on",
        pointFormat: "Point %d",
        pointTempFormat: "Point %d temperature, °C",
        pointSpeedFormat: "Point %d speed, percent",
        stepTempFormat: "Point %d temperature stepper",
        stepSpeedFormat: "Point %d speed stepper",
        chartLabelFormat: "Fan curve. Stock curve dashed, draft solid with five points, 100%% by %d °C.",
        limitFormat: "100%% by %d °C",
        curveOK: "The kext would accept it.",
        curveFailFormat: "Point %d: %@",
        ruleRange: "outside the range the driver takes.",
        ruleOrder: "temperatures must rise and speeds must not fall.",
        ruleFirst: "the first point must be at 30 °C or below.",
        ruleLastFormat: "the last point must be 100%% at %d °C or below.",
        ruleCooling: "it gives less air than the stock curve.",
        apply: "Apply curve",
        backToStock: "Back to stock",
        footerFormat: "With any accepted curve the fan reaches 100%% by %d °C. The first point must be at 30 °C or below; no point may give less air than the stock curve.",
        notePowerHeld: "A power limit is held. Applying the curve first returns the power limit to its start-up value: the kext never holds both.",
        noteCurveHeld: "A fan setting is held. Choosing a power limit first returns the fan to stock: the kext never holds both.",
        notChecked: "Not checked with this version of the kext.",
        chartKey: "Dashed: the stock curve. Solid: the draft.",
        applyHint: "Sends the curve to the kext. Return in a point field applies it too.",
        chartValueFormat: "Draft: %1$@. Stock curve: %2$@. %3$@.",
        chartValueDraftFormat: "Draft: %1$@. %2$@.",
        draftDiscarded: "Draft discarded.")

    static let es = GPUControlFanStrings(
        section: "Ventilador",
        curveToggle: "Curva personalizada",
        zeroRpmToggle: "Ventilador siempre girando",
        pointFormat: "Punto %d",
        pointTempFormat: "Temperatura del punto %d, °C",
        pointSpeedFormat: "Velocidad del punto %d, porcentaje",
        stepTempFormat: "Paso de temperatura del punto %d",
        stepSpeedFormat: "Paso de velocidad del punto %d",
        chartLabelFormat: "Curva del ventilador. En trazos, la curva de fábrica; en línea llena, la curva en edición, con cinco puntos; 100%% a %d °C.",
        limitFormat: "100%% a %d °C",
        curveOK: "El kext la aceptaría.",
        curveFailFormat: "Punto %d: %@",
        ruleRange: "fuera del rango que acepta el controlador.",
        ruleOrder: "las temperaturas tienen que subir y las velocidades no pueden bajar.",
        ruleFirst: "el primer punto tiene que estar a 30 °C o menos.",
        ruleLastFormat: "el último punto tiene que ser 100%% a %d °C o menos.",
        ruleCooling: "da menos aire que la curva de fábrica.",
        apply: "Aplicar curva",
        backToStock: "Volver a los valores de fábrica",
        footerFormat: "Con cualquier curva aceptada el ventilador llega al 100%% a %d °C. El primer punto tiene que estar a 30 °C o menos; ningún punto puede dar menos aire que la de fábrica.",
        notePowerHeld: "Hay un límite de potencia puesto. Al aplicar la curva, primero el límite vuelve a su valor de arranque: el kext nunca mantiene las dos cosas.",
        noteCurveHeld: "Hay un ajuste del ventilador puesto. Al elegir un límite de potencia, primero el ventilador vuelve a los valores de fábrica: el kext nunca mantiene las dos cosas.",
        notChecked: "No comprobado con esta versión del kext.",
        chartKey: "En trazos, la curva de fábrica; en línea llena, la curva en edición.",
        applyHint: "Manda la curva al kext. La tecla Retorno en un campo de punto también la aplica.",
        chartValueFormat: "Curva en edición: %1$@. Curva de fábrica: %2$@. %3$@.",
        chartValueDraftFormat: "Curva en edición: %1$@. %2$@.",
        draftDiscarded: "Se descartó la curva en edición.")

    static let ptBR = GPUControlFanStrings(
        section: "Ventoinha",
        curveToggle: "Curva personalizada",
        zeroRpmToggle: "Ventoinha sempre girando",
        pointFormat: "Ponto %d",
        pointTempFormat: "Temperatura do ponto %d, °C",
        pointSpeedFormat: "Velocidade do ponto %d, porcentagem",
        stepTempFormat: "Ajuste de temperatura do ponto %d",
        stepSpeedFormat: "Ajuste de velocidade do ponto %d",
        chartLabelFormat: "Curva da ventoinha. Curva de fábrica tracejada, rascunho em linha cheia com cinco pontos, 100%% a %d °C.",
        limitFormat: "100%% a %d °C",
        curveOK: "O kext aceitaria.",
        curveFailFormat: "Ponto %d: %@",
        ruleRange: "fora da faixa que o driver aceita.",
        ruleOrder: "as temperaturas têm que subir e as velocidades não podem cair.",
        ruleFirst: "o primeiro ponto tem que estar a 30 °C ou menos.",
        ruleLastFormat: "o último ponto tem que ser 100%% a %d °C ou menos.",
        ruleCooling: "dá menos ar que a curva de fábrica.",
        apply: "Aplicar curva",
        backToStock: "Voltar ao padrão",
        footerFormat: "Com qualquer curva aceita a ventoinha chega a 100%% a %d °C. O primeiro ponto tem que estar a 30 °C ou menos; nenhum ponto pode dar menos ar que a de fábrica.",
        notePowerHeld: "Há um limite de energia mantido. Ao aplicar a curva, primeiro o limite volta ao valor de inicialização: o kext nunca mantém os dois.",
        noteCurveHeld: "Há um ajuste da ventoinha mantido. Ao escolher um limite de energia, primeiro a ventoinha volta ao padrão: o kext nunca mantém os dois.",
        notChecked: "Não verificado com esta versão do kext.",
        chartKey: "Tracejada, a curva de fábrica; em linha cheia, o rascunho.",
        applyHint: "Envia a curva ao kext. Return num campo de ponto também a aplica.",
        chartValueFormat: "Rascunho: %1$@. Curva de fábrica: %2$@. %3$@.",
        chartValueDraftFormat: "Rascunho: %1$@. %2$@.",
        draftDiscarded: "Rascunho descartado.")

    static let tr = GPUControlFanStrings(
        section: "Fan",
        curveToggle: "Özel eğri",
        zeroRpmToggle: "Fan hep dönsün",
        pointFormat: "Nokta %d",
        pointTempFormat: "Nokta %d sıcaklığı, °C",
        pointSpeedFormat: "Nokta %d hızı, yüzde",
        stepTempFormat: "Nokta %d sıcaklık adımı",
        stepSpeedFormat: "Nokta %d hız adımı",
        chartLabelFormat: "Fan eğrisi. Fabrika eğrisi kesikli, taslak beş noktalı düz çizgi, %d °C'de %%100.",
        limitFormat: "%d °C'de %%100",
        curveOK: "Kext bunu kabul eder.",
        curveFailFormat: "Nokta %d: %@",
        ruleRange: "sürücünün kabul ettiği aralığın dışında.",
        ruleOrder: "sıcaklıklar artmalı ve hızlar düşmemeli.",
        ruleFirst: "ilk nokta 30 °C veya altında olmalı.",
        ruleLastFormat: "son nokta %d °C veya altında %%100 olmalı.",
        ruleCooling: "fabrika eğrisinden daha az hava veriyor.",
        apply: "Eğriyi uygula",
        backToStock: "Fabrika ayarlarına dön",
        footerFormat: "Kabul edilen her eğriyle fan %d °C'de %%100'e ulaşır. İlk nokta 30 °C veya altında olmalı; hiçbir nokta fabrika eğrisinden az hava veremez.",
        notePowerHeld: "Bir güç sınırı tutuluyor. Eğriyi uygulamak önce güç sınırını başlangıç değerine döndürür: kext ikisini birlikte tutmaz.",
        noteCurveHeld: "Bir fan ayarı tutuluyor. Güç sınırı seçmek önce fanı fabrika ayarına döndürür: kext ikisini birlikte tutmaz.",
        notChecked: "Kext'in bu sürümüyle denetlenmedi.",
        chartKey: "Kesikli çizgi fabrika eğrisi, düz çizgi taslaktır.",
        applyHint: "Eğriyi kext'e gönderir. Bir nokta alanında Return tuşu da uygular.",
        chartValueFormat: "Taslak: %1$@. Fabrika eğrisi: %2$@. %3$@.",
        chartValueDraftFormat: "Taslak: %1$@. %2$@.",
        draftDiscarded: "Taslak atıldı.")

    static let ru = GPUControlFanStrings(
        section: "Вентилятор",
        curveToggle: "Своя кривая",
        zeroRpmToggle: "Вентилятор всегда вращается",
        pointFormat: "Точка %d",
        pointTempFormat: "Температура точки %d, °C",
        pointSpeedFormat: "Скорость точки %d, процент",
        stepTempFormat: "Шаг температуры точки %d",
        stepSpeedFormat: "Шаг скорости точки %d",
        chartLabelFormat: "Кривая вентилятора. Заводская кривая штрихами, черновик сплошной линией с пятью точками, 100%% при %d °C.",
        limitFormat: "100%% при %d °C",
        curveOK: "Kext её примет.",
        curveFailFormat: "Точка %d: %@",
        ruleRange: "вне диапазона, который принимает драйвер.",
        ruleOrder: "температуры должны расти, а скорости не должны падать.",
        ruleFirst: "первая точка должна быть при 30 °C или ниже.",
        ruleLastFormat: "последняя точка должна быть 100%% при %d °C или ниже.",
        ruleCooling: "она даёт меньше воздуха, чем заводская кривая.",
        apply: "Применить кривую",
        backToStock: "Вернуть заводские настройки",
        footerFormat: "С любой принятой кривой вентилятор достигает 100%% при %d °C. Первая точка должна быть при 30 °C или ниже; ни одна точка не может давать меньше воздуха, чем заводская кривая.",
        notePowerHeld: "Удерживается лимит мощности. Применение кривой сначала вернёт лимит к значению загрузки: kext никогда не удерживает оба.",
        noteCurveHeld: "Удерживается настройка вентилятора. Выбор лимита мощности сначала вернёт вентилятор к заводским значениям: kext никогда не удерживает оба.",
        notChecked: "Не проверено с этой версией kext.",
        chartKey: "Штрихами — заводская кривая, сплошной линией — черновик.",
        applyHint: "Отправляет кривую в kext. Клавиша Return в поле точки тоже её применяет.",
        chartValueFormat: "Черновик: %1$@. Заводская кривая: %2$@. %3$@.",
        chartValueDraftFormat: "Черновик: %1$@. %2$@.",
        draftDiscarded: "Черновик отменён.")

    static let sk = GPUControlFanStrings(
        section: "Ventilátor",
        curveToggle: "Vlastná krivka",
        zeroRpmToggle: "Ventilátor stále v chode",
        pointFormat: "Bod %d",
        pointTempFormat: "Teplota bodu %d, °C",
        pointSpeedFormat: "Rýchlosť bodu %d, percento",
        stepTempFormat: "Krok teploty bodu %d",
        stepSpeedFormat: "Krok rýchlosti bodu %d",
        chartLabelFormat: "Krivka ventilátora. Továrenská krivka čiarkovane, koncept plnou čiarou s piatimi bodmi, 100%% pri %d °C.",
        limitFormat: "100%% pri %d °C",
        curveOK: "Kext by ju prijal.",
        curveFailFormat: "Bod %d: %@",
        ruleRange: "mimo rozsahu, ktorý ovládač prijíma.",
        ruleOrder: "teploty musia stúpať a rýchlosti nesmú klesať.",
        ruleFirst: "prvý bod musí byť pri 30 °C alebo nižšie.",
        ruleLastFormat: "posledný bod musí byť 100%% pri %d °C alebo nižšie.",
        ruleCooling: "dáva menej vzduchu než továrenská krivka.",
        apply: "Použiť krivku",
        backToStock: "Späť na továrenské nastavenia",
        footerFormat: "S každou prijatou krivkou ventilátor dosiahne 100%% pri %d °C. Prvý bod musí byť pri 30 °C alebo nižšie; žiadny bod nesmie dať menej vzduchu než továrenská krivka.",
        notePowerHeld: "Drží sa limit príkonu. Použitie krivky najprv vráti limit na štartovaciu hodnotu: kext nikdy nedrží oboje.",
        noteCurveHeld: "Drží sa nastavenie ventilátora. Výber limitu výkonu najprv vráti ventilátor na továrenské hodnoty: kext nikdy nedrží oboje.",
        notChecked: "Neoverené s touto verziou kextu.",
        chartKey: "Čiarkovane továrenská krivka, plnou čiarou koncept.",
        applyHint: "Pošle krivku do kextu. Použije ju aj kláves Return v poli bodu.",
        chartValueFormat: "Koncept: %1$@. Továrenská krivka: %2$@. %3$@.",
        chartValueDraftFormat: "Koncept: %1$@. %2$@.",
        draftDiscarded: "Koncept zahodený.")

    static let de = GPUControlFanStrings(
        section: "Lüfter",
        curveToggle: "Eigene Kurve",
        zeroRpmToggle: "Lüfter läuft immer",
        pointFormat: "Punkt %d",
        pointTempFormat: "Temperatur Punkt %d, °C",
        pointSpeedFormat: "Drehzahl Punkt %d, Prozent",
        stepTempFormat: "Temperaturschritt für Punkt %d",
        stepSpeedFormat: "Drehzahlschritt für Punkt %d",
        chartLabelFormat: "Lüfterkurve. Werkskurve gestrichelt, Entwurf durchgezogen mit fünf Punkten, 100 %% bei %d °C.",
        limitFormat: "100 %% bei %d °C",
        curveOK: "Der Kext würde sie annehmen.",
        curveFailFormat: "Punkt %d: %@",
        ruleRange: "außerhalb des Bereichs, den der Treiber annimmt.",
        ruleOrder: "Temperaturen müssen steigen, Drehzahlen dürfen nicht fallen.",
        ruleFirst: "Der erste Punkt muss bei 30 °C oder darunter liegen.",
        ruleLastFormat: "Der letzte Punkt muss 100 %% bei %d °C oder darunter sein.",
        ruleCooling: "Die Kurve gibt dort weniger Luft als die Werkskurve.",
        apply: "Kurve anwenden",
        backToStock: "Zurück zu den Werkswerten",
        footerFormat: "Mit jeder angenommenen Kurve erreicht der Lüfter 100 %% bei %d °C. Der erste Punkt muss bei 30 °C oder darunter liegen; kein Punkt darf weniger Luft geben als die Werkskurve.",
        notePowerHeld: "Ein Leistungslimit wird gehalten. Beim Anwenden der Kurve geht das Limit zuerst auf seinen Startwert zurück: Der Kext hält nie beides.",
        noteCurveHeld: "Eine Lüftereinstellung wird gehalten. Beim Wählen eines Leistungslimits geht der Lüfter zuerst auf Werkseinstellung zurück: Der Kext hält nie beides.",
        notChecked: "Mit dieser Kext-Version nicht geprüft.",
        chartKey: "Gestrichelt die Werkskurve, durchgezogen der Entwurf.",
        applyHint: "Sendet die Kurve an den Kext. Auch die Eingabetaste in einem Punktfeld wendet sie an.",
        chartValueFormat: "Entwurf: %1$@. Werkskurve: %2$@. %3$@.",
        chartValueDraftFormat: "Entwurf: %1$@. %2$@.",
        draftDiscarded: "Entwurf verworfen.")

    static let fr = GPUControlFanStrings(
        section: "Ventilateur",
        curveToggle: "Courbe personnalisée",
        zeroRpmToggle: "Ventilateur toujours actif",
        pointFormat: "Point %d",
        pointTempFormat: "Température du point %d, °C",
        pointSpeedFormat: "Vitesse du point %d, pourcentage",
        stepTempFormat: "Incrément de température du point %d",
        stepSpeedFormat: "Incrément de vitesse du point %d",
        chartLabelFormat: "Courbe du ventilateur. Courbe d’usine en pointillés, brouillon en trait plein avec cinq points, 100 %% à %d °C.",
        limitFormat: "100 %% à %d °C",
        curveOK: "Le kext l’accepterait.",
        curveFailFormat: "Point %d : %@",
        ruleRange: "hors de la plage acceptée par le pilote.",
        ruleOrder: "les températures doivent monter et les vitesses ne doivent pas baisser.",
        ruleFirst: "le premier point doit être à 30 °C ou moins.",
        ruleLastFormat: "le dernier point doit être à 100 %% à %d °C ou moins.",
        ruleCooling: "elle donne moins d’air que la courbe d’usine.",
        apply: "Appliquer la courbe",
        backToStock: "Revenir aux réglages d’usine",
        footerFormat: "Avec toute courbe acceptée, le ventilateur atteint 100 %% à %d °C. Le premier point doit être à 30 °C ou moins ; aucun point ne peut donner moins d’air que la courbe d’usine.",
        notePowerHeld: "Une limite de puissance est maintenue. Appliquer la courbe remet d’abord la limite à sa valeur de démarrage : le kext ne maintient jamais les deux.",
        noteCurveHeld: "Un réglage du ventilateur est maintenu. Choisir une limite de puissance remet d’abord le ventilateur aux réglages d’usine : le kext ne maintient jamais les deux.",
        notChecked: "Non vérifié avec cette version du kext.",
        chartKey: "En pointillés, la courbe d’usine ; en trait plein, le brouillon.",
        applyHint: "Envoie la courbe au kext. La touche Retour dans un champ de point l’applique aussi.",
        chartValueFormat: "Brouillon : %1$@. Courbe d’usine : %2$@. %3$@.",
        chartValueDraftFormat: "Brouillon : %1$@. %2$@.",
        draftDiscarded: "Brouillon abandonné.")

    static let it = GPUControlFanStrings(
        section: "Ventola",
        curveToggle: "Curva personalizzata",
        zeroRpmToggle: "Ventola sempre accesa",
        pointFormat: "Punto %d",
        pointTempFormat: "Temperatura del punto %d, °C",
        pointSpeedFormat: "Velocità del punto %d, percentuale",
        stepTempFormat: "Passo di temperatura del punto %d",
        stepSpeedFormat: "Passo di velocità del punto %d",
        chartLabelFormat: "Curva della ventola. Curva di fabbrica tratteggiata, bozza in linea continua con cinque punti, 100%% a %d °C.",
        limitFormat: "100%% a %d °C",
        curveOK: "Il kext l’accetterebbe.",
        curveFailFormat: "Punto %d: %@",
        ruleRange: "fuori dall’intervallo che il driver accetta.",
        ruleOrder: "le temperature devono salire e le velocità non devono scendere.",
        ruleFirst: "il primo punto deve stare a 30 °C o meno.",
        ruleLastFormat: "l’ultimo punto deve essere al 100%% a %d °C o meno.",
        ruleCooling: "dà meno aria della curva di fabbrica.",
        apply: "Applica curva",
        backToStock: "Torna ai valori di fabbrica",
        footerFormat: "Con qualsiasi curva accettata la ventola arriva al 100%% a %d °C. Il primo punto deve stare a 30 °C o meno; nessun punto può dare meno aria della curva di fabbrica.",
        notePowerHeld: "È mantenuto un limite di potenza. Applicando la curva, prima il limite torna al valore di avvio: il kext non mantiene mai entrambi.",
        noteCurveHeld: "È mantenuta un’impostazione della ventola. Scegliendo un limite di potenza, prima la ventola torna ai valori di fabbrica: il kext non mantiene mai entrambi.",
        notChecked: "Non verificato con questa versione del kext.",
        chartKey: "Tratteggiata la curva di fabbrica, in linea continua la bozza.",
        applyHint: "Invia la curva al kext. Anche il tasto Invio in un campo del punto la applica.",
        chartValueFormat: "Bozza: %1$@. Curva di fabbrica: %2$@. %3$@.",
        chartValueDraftFormat: "Bozza: %1$@. %2$@.",
        draftDiscarded: "Bozza scartata.")

    static let ja = GPUControlFanStrings(
        section: "ファン",
        curveToggle: "カスタムカーブ",
        zeroRpmToggle: "ファンを常に回す",
        pointFormat: "ポイント %d",
        pointTempFormat: "ポイント %d の温度、°C",
        pointSpeedFormat: "ポイント %d の速度、パーセント",
        stepTempFormat: "ポイント %d の温度ステッパー",
        stepSpeedFormat: "ポイント %d の速度ステッパー",
        chartLabelFormat: "ファンカーブ。純正カーブは破線、下書きは5点の実線、%d °C で 100%%。",
        limitFormat: "%d °C で 100%%",
        curveOK: "kext はこれを受け入れます。",
        curveFailFormat: "ポイント %d: %@",
        ruleRange: "ドライバーが受け付ける範囲外です。",
        ruleOrder: "温度は上がり、速度は下がってはいけません。",
        ruleFirst: "最初のポイントは 30 °C 以下にしてください。",
        ruleLastFormat: "最後のポイントは %d °C 以下で 100%% にしてください。",
        ruleCooling: "純正カーブより風量が少なくなります。",
        apply: "カーブを適用",
        backToStock: "純正に戻す",
        footerFormat: "受け入れられたカーブでは、ファンは %d °C で 100%% に達します。最初のポイントは 30 °C 以下で、どのポイントも純正カーブより風量を少なくできません。",
        notePowerHeld: "電力制限が保持されています。カーブを適用すると、先に電力制限が起動時の値に戻ります。kext は両方を同時に保持しません。",
        noteCurveHeld: "ファンの設定が保持されています。電力制限を選ぶと、先にファンが純正に戻ります。kext は両方を同時に保持しません。",
        notChecked: "このバージョンの kext では確認されていません。",
        chartKey: "破線は純正カーブ、実線は下書きです。",
        applyHint: "カーブを kext に送ります。点のフィールドで Return キーを押しても適用されます。",
        chartValueFormat: "下書き: %1$@。純正カーブ: %2$@。%3$@。",
        chartValueDraftFormat: "下書き: %1$@。%2$@。",
        draftDiscarded: "下書きを破棄しました。")

    static let ko = GPUControlFanStrings(
        section: "팬",
        curveToggle: "사용자 곡선",
        zeroRpmToggle: "팬 항상 켜기",
        pointFormat: "지점 %d",
        pointTempFormat: "지점 %d 온도, °C",
        pointSpeedFormat: "지점 %d 속도, 퍼센트",
        stepTempFormat: "지점 %d 온도 조절",
        stepSpeedFormat: "지점 %d 속도 조절",
        chartLabelFormat: "팬 곡선. 기본 곡선은 점선, 초안은 5개 지점의 실선, %d °C에서 100%%.",
        limitFormat: "%d °C에서 100%%",
        curveOK: "kext가 받아들입니다.",
        curveFailFormat: "지점 %d: %@",
        ruleRange: "드라이버가 받아들이는 범위를 벗어났습니다.",
        ruleOrder: "온도는 올라가야 하고 속도는 내려가면 안 됩니다.",
        ruleFirst: "첫 지점은 30 °C 이하여야 합니다.",
        ruleLastFormat: "마지막 지점은 %d °C 이하에서 100%%여야 합니다.",
        ruleCooling: "기본 곡선보다 바람이 적습니다.",
        apply: "곡선 적용",
        backToStock: "기본값으로 돌아가기",
        footerFormat: "받아들여진 곡선에서는 팬이 %d °C에서 100%%에 도달합니다. 첫 지점은 30 °C 이하여야 하고, 어떤 지점도 기본 곡선보다 바람이 적을 수 없습니다.",
        notePowerHeld: "전력 한도가 유지되고 있습니다. 곡선을 적용하면 먼저 전력 한도가 시동 값으로 돌아갑니다. kext는 둘을 함께 유지하지 않습니다.",
        noteCurveHeld: "팬 설정이 유지되고 있습니다. 전력 한도를 선택하면 먼저 팬이 기본값으로 돌아갑니다. kext는 둘을 함께 유지하지 않습니다.",
        notChecked: "이 버전의 kext로 확인되지 않았습니다.",
        chartKey: "점선은 기본 곡선, 실선은 초안입니다.",
        applyHint: "곡선을 kext로 보냅니다. 점 필드에서 Return 키를 눌러도 적용됩니다.",
        chartValueFormat: "초안: %1$@. 기본 곡선: %2$@. %3$@.",
        chartValueDraftFormat: "초안: %1$@. %2$@.",
        draftDiscarded: "초안을 버렸습니다.")

    static let zhHans = GPUControlFanStrings(
        section: "风扇",
        curveToggle: "自定义曲线",
        zeroRpmToggle: "风扇始终转动",
        pointFormat: "点 %d",
        pointTempFormat: "点 %d 的温度，°C",
        pointSpeedFormat: "点 %d 的转速，百分比",
        stepTempFormat: "点 %d 温度步进器",
        stepSpeedFormat: "点 %d 转速步进器",
        chartLabelFormat: "风扇曲线。原厂曲线为虚线，草稿为带五个点的实线，%d °C 时 100%%。",
        limitFormat: "%d °C 时 100%%",
        curveOK: "kext 会接受。",
        curveFailFormat: "点 %d：%@",
        ruleRange: "超出驱动程序接受的范围。",
        ruleOrder: "温度必须上升，转速不能下降。",
        ruleFirst: "第一个点必须为 30 °C 或更低。",
        ruleLastFormat: "最后一个点必须在 %d °C 或更低时为 100%%。",
        ruleCooling: "它的风量比原厂曲线少。",
        apply: "应用曲线",
        backToStock: "返回出厂值",
        footerFormat: "使用任何被接受的曲线，风扇在 %d °C 时达到 100%%。第一个点必须为 30 °C 或更低；任何点的风量都不能少于原厂曲线。",
        notePowerHeld: "当前设有功率上限。应用曲线会先使功率上限返回启动值：kext 绝不会同时维持两者。",
        noteCurveHeld: "正在维持风扇设置。选择功率上限会先使风扇返回出厂设置：kext 绝不会同时维持两者。",
        notChecked: "未用此版本的 kext 检查。",
        chartKey: "虚线为原厂曲线，实线为草稿。",
        applyHint: "将曲线发送到 kext。在点的输入框中按 Return 键也会应用。",
        chartValueFormat: "草稿：%1$@。原厂曲线：%2$@。%3$@。",
        chartValueDraftFormat: "草稿：%1$@。%2$@。",
        draftDiscarded: "已放弃草稿。")

    static let zhTW = GPUControlFanStrings(
        section: "風扇",
        curveToggle: "自訂曲線",
        zeroRpmToggle: "風扇始終轉動",
        pointFormat: "點 %d",
        pointTempFormat: "點 %d 的溫度，°C",
        pointSpeedFormat: "點 %d 的轉速，百分比",
        stepTempFormat: "點 %d 溫度步進器",
        stepSpeedFormat: "點 %d 轉速步進器",
        chartLabelFormat: "風扇曲線。原廠曲線為虛線，草稿為含五個點的實線，%d °C 時 100%%。",
        limitFormat: "%d °C 時 100%%",
        curveOK: "kext 會接受。",
        curveFailFormat: "點 %d：%@",
        ruleRange: "超出驅動程式接受的範圍。",
        ruleOrder: "溫度必須上升，轉速不能下降。",
        ruleFirst: "第一個點必須為 30 °C 或更低。",
        ruleLastFormat: "最後一個點必須在 %d °C 或更低時為 100%%。",
        ruleCooling: "它的風量比原廠曲線少。",
        apply: "套用曲線",
        backToStock: "返回原廠值",
        footerFormat: "使用任何被接受的曲線，風扇在 %d °C 時達到 100%%。第一個點必須為 30 °C 或更低；任何點的風量都不能少於原廠曲線。",
        notePowerHeld: "目前設有功率上限。套用曲線會先使功率上限回到啟動值：kext 絕不會同時維持兩者。",
        noteCurveHeld: "正在維持風扇設定。選擇功率上限會先使風扇回到原廠設定：kext 絕不會同時維持兩者。",
        notChecked: "未用此版本的 kext 檢查。",
        chartKey: "虛線為原廠曲線，實線為草稿。",
        applyHint: "將曲線傳送到 kext。在點的欄位中按 Return 鍵也會套用。",
        chartValueFormat: "草稿：%1$@。原廠曲線：%2$@。%3$@。",
        chartValueDraftFormat: "草稿：%1$@。%2$@。",
        draftDiscarded: "已捨棄草稿。")

    static let uk = GPUControlFanStrings(
        section: "Вентилятор",
        curveToggle: "Власна крива",
        zeroRpmToggle: "Вентилятор завжди обертається",
        pointFormat: "Точка %d",
        pointTempFormat: "Температура точки %d, °C",
        pointSpeedFormat: "Швидкість точки %d, відсоток",
        stepTempFormat: "Крок температури точки %d",
        stepSpeedFormat: "Крок швидкості точки %d",
        chartLabelFormat: "Крива вентилятора. Заводська крива пунктиром, чернетка суцільною лінією з п’ятьма точками, 100%% за %d °C.",
        limitFormat: "100%% за %d °C",
        curveOK: "Kext її прийме.",
        curveFailFormat: "Точка %d: %@",
        ruleRange: "поза діапазоном, який приймає драйвер.",
        ruleOrder: "температури мають зростати, а швидкості не можуть падати.",
        ruleFirst: "перша точка має бути за 30 °C або нижче.",
        ruleLastFormat: "остання точка має бути 100%% за %d °C або нижче.",
        ruleCooling: "вона дає менше повітря, ніж заводська крива.",
        apply: "Застосувати криву",
        backToStock: "До заводських значень",
        footerFormat: "З будь-якою прийнятою кривою вентилятор досягає 100%% за %d °C. Перша точка має бути за 30 °C або нижче; жодна точка не може давати менше повітря, ніж заводська крива.",
        notePowerHeld: "Утримується ліміт потужності. Застосування кривої спершу поверне ліміт до значення завантаження: kext ніколи не утримує обидва.",
        noteCurveHeld: "Утримується налаштування вентилятора. Вибір ліміту потужності спершу поверне вентилятор до заводських значень: kext ніколи не утримує обидва.",
        notChecked: "Не перевірено з цією версією kext.",
        chartKey: "Пунктиром — заводська крива, суцільною лінією — чернетка.",
        applyHint: "Надсилає криву в kext. Клавіша Return у полі точки теж її застосовує.",
        chartValueFormat: "Чернетка: %1$@. Заводська крива: %2$@. %3$@.",
        chartValueDraftFormat: "Чернетка: %1$@. %2$@.",
        draftDiscarded: "Чернетку скасовано.")
}
