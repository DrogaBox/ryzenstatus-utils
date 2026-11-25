// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The GFX voltage and Overclock sections of Settings > GPU control
/// (GPUSensors 0.9.0). Built like `GPUControlClockStrings`; the power note
/// and the wait of a switch reuse the clock section's texts.
struct GPUControlOverclockStrings {
    // The GFX voltage section.
    /// The section's header, and the slider's VoiceOver label.
    let voltSection: String
    /// VoiceOver: the mV field.
    let voltFieldLabel: String
    /// VoiceOver: the stepper; %d = its step in mV.
    let voltStepperFormat: String
    let voltToggle: String
    /// %d = the stock voltage in mV.
    let voltStockFormat: String
    /// The slider's VoiceOver help: %1$d = the lowest value, %2$d = stock,
    /// both in mV.
    let voltSliderHelpFormat: String
    /// %1$d = the lowest value, %2$d = stock, %3$d = the step, all in mV.
    let voltOutOfRangeFormat: String
    /// %d = one step below stock, in mV.
    let voltRecommendedFormat: String
    /// The button that puts the starting point into the control.
    let voltUseRecommended: String
    /// The button that sends the value in the control.
    let voltApply: String
    let voltFooter: String

    // The Overclock section.
    let ocSection: String
    let ocToggle: String
    /// Under the switch: what can and cannot happen.
    let ocWarning: String
    /// The raised GFX maximum's row, and its slider's VoiceOver label.
    let ocGfxLabel: String
    /// VoiceOver: the MHz field.
    let ocGfxFieldLabel: String
    /// VoiceOver: the stepper; %d = its step in MHz.
    let ocGfxStepperFormat: String
    /// The slider's VoiceOver help: %1$d = stock, %2$d = the card's
    /// maximum, both in MHz.
    let ocGfxSliderHelpFormat: String
    /// %d = the card's own maximum in MHz, under the slider's top end.
    let ocGfxTopFormat: String
    /// The raised power limit's pop-up.
    let ocPowerLabel: String
    /// VoiceOver's hint on that pop-up.
    let ocPowerHint: String
    let ocFooter: String

    var all: [String] {
        [voltSection, voltFieldLabel, voltStepperFormat, voltToggle, voltStockFormat, voltSliderHelpFormat,
         voltOutOfRangeFormat, voltRecommendedFormat, voltUseRecommended, voltApply, voltFooter,
         ocSection, ocToggle, ocWarning, ocGfxLabel, ocGfxFieldLabel, ocGfxStepperFormat, ocGfxSliderHelpFormat,
         ocGfxTopFormat, ocPowerLabel, ocPowerHint, ocFooter]
    }
}

extension FeatureStrings {
    static func gpuControlOverclock(_ language: AppLanguage) -> GPUControlOverclockStrings {
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

extension GPUControlOverclockStrings {
    static let enUS = GPUControlOverclockStrings(
        voltSection: "GFX voltage",
        voltFieldLabel: "GFX voltage in mV",
        voltStepperFormat: "GFX voltage, steps of %d mV",
        voltToggle: "Lower the GFX voltage",
        voltStockFormat: "Stock (%d mV)",
        voltSliderHelpFormat: "From %1$d mV to the stock voltage, %2$d mV. Only lowers it; the value is sent when you stop moving it.",
        voltOutOfRangeFormat: "Choose a value from %1$d to %2$d mV, in steps of %3$d mV from stock.",
        voltRecommendedFormat: "Recommended starting point: %d mV. A starting point to test, not a guarantee.",
        voltUseRecommended: "Use Starting Point",
        voltApply: "Apply",
        voltFooter: "Lowers the whole GPU voltage curve by the difference to stock: less heat and less power. If it is too low, the GPU can freeze, reset its driver or show a black screen. Go down 25 mV at a time, test with a game or a benchmark, and stay 10–20 mV above the lowest value that was stable. It goes back to stock when RyzenStatus quits, on restart and after sleep. Silicon varies from card to card.",
        ocSection: "Overclock",
        ocToggle: "Allow overclocking",
        ocWarning: "Inside AMD’s own limits for this card nothing can burn, but a value can be unstable: the GPU can freeze or reset its driver. Everything goes back to stock when you turn this off, when RyzenStatus quits, on restart and after sleep, and the watchdog puts stock back at 95 °C.",
        ocGfxLabel: "GFX maximum above stock",
        ocGfxFieldLabel: "Raised GFX maximum clock in MHz",
        ocGfxStepperFormat: "Raised GFX maximum clock, steps of %d MHz",
        ocGfxSliderHelpFormat: "From the stock maximum, %1$d MHz, to the card’s maximum, %2$d MHz. The value is sent when you stop moving it.",
        ocGfxTopFormat: "Card maximum (%d MHz)",
        ocPowerLabel: "Power limit above start-up",
        ocPowerHint: "Applies when chosen, up to the card’s own ceiling.",
        ocFooter: "More clock usually needs more power to gain anything. The kext holds one thing at a time: a power limit and the clock, fan or voltage settings are never held together. Turning overclocking off puts back whatever it raised.")

    static let es = GPUControlOverclockStrings(
        voltSection: "Voltaje de GFX",
        voltFieldLabel: "Voltaje de GFX en mV",
        voltStepperFormat: "Voltaje de GFX, pasos de %d mV",
        voltToggle: "Bajar el voltaje de GFX",
        voltStockFormat: "De fábrica (%d mV)",
        voltSliderHelpFormat: "De %1$d mV al voltaje de fábrica, %2$d mV. Solo lo baja; el valor se manda cuando dejas de moverlo.",
        voltOutOfRangeFormat: "Elige un valor entre %1$d y %2$d mV, en pasos de %3$d mV desde el de fábrica.",
        voltRecommendedFormat: "Punto de partida recomendado: %d mV. Es un punto de partida para probar, no una garantía.",
        voltUseRecommended: "Usar punto de partida",
        voltApply: "Aplicar",
        voltFooter: "Baja toda la curva de voltaje de la GPU en la diferencia con el de fábrica: menos calor y menos consumo. Si queda demasiado bajo, la GPU puede congelarse, reiniciar su driver o dejar la pantalla en negro. Baja 25 mV cada vez, prueba con un juego o un benchmark y quédate 10–20 mV por encima del valor más bajo que fue estable. Vuelve al de fábrica al salir de RyzenStatus, al reiniciar y después del reposo. Cada chip es distinto, aun en el mismo modelo de tarjeta.",
        ocSection: "Overclock",
        ocToggle: "Permitir overclock",
        ocWarning: "Dentro de los límites que AMD fija para esta tarjeta nada se puede quemar, pero un valor puede ser inestable: la GPU puede congelarse o reiniciar su driver. Todo vuelve a los valores de fábrica al apagar esto, al salir de RyzenStatus, al reiniciar y después del reposo, y el vigilante vuelve a los valores de fábrica a los 95 °C.",
        ocGfxLabel: "Máximo de GFX sobre el de fábrica",
        ocGfxFieldLabel: "Reloj máximo de GFX subido, en MHz",
        ocGfxStepperFormat: "Reloj máximo de GFX subido, pasos de %d MHz",
        ocGfxSliderHelpFormat: "Del máximo de fábrica, %1$d MHz, al máximo de la tarjeta, %2$d MHz. El valor se manda cuando dejas de moverlo.",
        ocGfxTopFormat: "Máximo de la tarjeta (%d MHz)",
        ocPowerLabel: "Límite de potencia sobre el de arranque",
        ocPowerHint: "Se aplica al elegirlo, hasta el tope de la propia tarjeta.",
        ocFooter: "Para ganar algo, más reloj suele necesitar más potencia. El kext mantiene una sola cosa a la vez: un límite de potencia y los ajustes de reloj, ventilador o voltaje nunca se mantienen juntos. Al apagar el overclock vuelve todo lo que había subido.")

    static let ptBR = GPUControlOverclockStrings(
        voltSection: "Tensão da GFX",
        voltFieldLabel: "Tensão da GFX em mV",
        voltStepperFormat: "Tensão da GFX, passos de %d mV",
        voltToggle: "Reduzir a tensão da GFX",
        voltStockFormat: "Padrão (%d mV)",
        voltSliderHelpFormat: "De %1$d mV à tensão padrão, %2$d mV. Só reduz; o valor é enviado quando você para de movê-lo.",
        voltOutOfRangeFormat: "Escolha um valor entre %1$d e %2$d mV, em passos de %3$d mV a partir do padrão.",
        voltRecommendedFormat: "Ponto de partida recomendado: %d mV. Um ponto de partida para testar, não uma garantia.",
        voltUseRecommended: "Usar ponto de partida",
        voltApply: "Aplicar",
        voltFooter: "Reduz toda a curva de tensão da GPU pela diferença em relação ao padrão: menos calor e menos consumo. Se ficar baixa demais, a GPU pode travar, reiniciar o driver ou deixar a tela preta. Desça 25 mV por vez, teste com um jogo ou benchmark e fique 10–20 mV acima do menor valor que foi estável. Volta ao padrão quando o RyzenStatus fecha, ao reiniciar e depois do repouso. Cada chip é diferente, mesmo no mesmo modelo de placa.",
        ocSection: "Overclock",
        ocToggle: "Permitir overclock",
        ocWarning: "Dentro dos limites da própria AMD para esta placa nada pode queimar, mas um valor pode ser instável: a GPU pode travar ou reiniciar o driver. Tudo volta ao padrão ao desligar isto, quando o RyzenStatus fecha, ao reiniciar e depois do repouso, e o vigilante restaura o padrão a 95 °C.",
        ocGfxLabel: "Máximo da GFX acima do padrão",
        ocGfxFieldLabel: "Clock máximo da GFX elevado em MHz",
        ocGfxStepperFormat: "Clock máximo da GFX elevado, passos de %d MHz",
        ocGfxSliderHelpFormat: "Do máximo padrão, %1$d MHz, ao máximo da placa, %2$d MHz. O valor é enviado quando você para de movê-lo.",
        ocGfxTopFormat: "Máximo da placa (%d MHz)",
        ocPowerLabel: "Limite de energia acima da inicialização",
        ocPowerHint: "Aplica ao escolher, até o teto da própria placa.",
        ocFooter: "Mais clock costuma precisar de mais energia para ganhar algo. O kext mantém uma coisa por vez: um limite de energia e ajustes de clock, ventoinha ou tensão nunca ficam juntos. Desligar o overclock devolve o que ele elevou.")

    static let tr = GPUControlOverclockStrings(
        voltSection: "GFX gerilimi",
        voltFieldLabel: "mV cinsinden GFX gerilimi",
        voltStepperFormat: "GFX gerilimi, %d mV adımlarla",
        voltToggle: "GFX gerilimini düşür",
        voltStockFormat: "Fabrika (%d mV)",
        voltSliderHelpFormat: "%1$d mV ile fabrika gerilimi %2$d mV arası. Yalnızca düşürür; değer, kaydırmayı bıraktığınızda gönderilir.",
        voltOutOfRangeFormat: "Fabrika değerinden %3$d mV adımlarla %1$d ile %2$d mV arasında bir değer seçin.",
        voltRecommendedFormat: "Önerilen başlangıç noktası: %d mV. Denemek için bir başlangıç noktasıdır, garanti değildir.",
        voltUseRecommended: "Başlangıç noktasını kullan",
        voltApply: "Uygula",
        voltFooter: "GPU'nun tüm gerilim eğrisini fabrika değerine olan fark kadar düşürür: daha az ısı ve daha az güç. Fazla düşükse GPU donabilir, sürücüsünü sıfırlayabilir veya siyah ekran gösterebilir. Her seferinde 25 mV düşürün, bir oyun veya benchmark ile deneyin ve kararlı kalan en düşük değerin 10–20 mV üstünde kalın. RyzenStatus kapanınca, yeniden başlatınca ve uykudan sonra fabrika değerine döner. Her çip farklıdır.",
        ocSection: "Hız aşırtma",
        ocToggle: "Hız aşırtmaya izin ver",
        ocWarning: "AMD'nin bu kart için koyduğu sınırlar içinde hiçbir şey yanamaz, ama bir değer kararsız olabilir: GPU donabilir veya sürücüsünü sıfırlayabilir. Bunu kapattığınızda, RyzenStatus kapanınca, yeniden başlatınca ve uykudan sonra her şey fabrika değerine döner; bekçi 95 °C'de fabrika değerlerini geri getirir.",
        ocGfxLabel: "Fabrika değerinin üstünde maks. GFX",
        ocGfxFieldLabel: "MHz cinsinden yükseltilmiş maks. GFX saat hızı",
        ocGfxStepperFormat: "Yükseltilmiş maks. GFX saat hızı, %d MHz adımlarla",
        ocGfxSliderHelpFormat: "Fabrika maksimumu %1$d MHz ile kartın maksimumu %2$d MHz arası. Değer, kaydırmayı bıraktığınızda gönderilir.",
        ocGfxTopFormat: "Kart maksimumu (%d MHz)",
        ocPowerLabel: "Başlangıç değerinin üstünde güç sınırı",
        ocPowerHint: "Seçildiğinde uygulanır, kartın kendi tavanına kadar.",
        ocFooter: "Daha yüksek saat hızı, bir kazanç sağlamak için genellikle daha fazla güç ister. Kext aynı anda tek bir şey tutar: güç sınırı ile saat hızı, fan veya gerilim ayarları asla birlikte tutulmaz. Hız aşırtmayı kapatmak, yükselttiği her şeyi geri alır.")

    static let ru = GPUControlOverclockStrings(
        voltSection: "Напряжение GFX",
        voltFieldLabel: "Напряжение GFX в мВ",
        voltStepperFormat: "Напряжение GFX, шаг %d мВ",
        voltToggle: "Снизить напряжение GFX",
        voltStockFormat: "Заводское (%d мВ)",
        voltSliderHelpFormat: "От %1$d мВ до заводского напряжения %2$d мВ. Только снижает; значение отправляется, когда вы отпускаете ползунок.",
        voltOutOfRangeFormat: "Выберите значение от %1$d до %2$d мВ с шагом %3$d мВ от заводского.",
        voltRecommendedFormat: "Рекомендуемая отправная точка: %d мВ. Это точка для проверки, а не гарантия.",
        voltUseRecommended: "Взять отправную точку",
        voltApply: "Применить",
        voltFooter: "Снижает всю кривую напряжения GPU на разницу с заводским: меньше нагрев и потребление. Если слишком низко, GPU может зависнуть, перезапустить драйвер или показать чёрный экран. Снижайте по 25 мВ, проверяйте игрой или бенчмарком и держитесь на 10–20 мВ выше самого низкого стабильного значения. Возвращается к заводскому при выходе из RyzenStatus, при перезагрузке и после сна. Каждый чип отличается.",
        ocSection: "Разгон",
        ocToggle: "Разрешить разгон",
        ocWarning: "В пределах, которые AMD задаёт для этой карты, ничего не сгорит, но значение может быть нестабильным: GPU может зависнуть или перезапустить драйвер. Всё возвращается к заводскому, когда вы выключаете это, при выходе из RyzenStatus, при перезагрузке и после сна, а сторож возвращает заводские значения при 95 °C.",
        ocGfxLabel: "Макс. частота GFX выше заводской",
        ocGfxFieldLabel: "Повышенная макс. частота GFX в МГц",
        ocGfxStepperFormat: "Повышенная макс. частота GFX, шаг %d МГц",
        ocGfxSliderHelpFormat: "От заводского максимума %1$d МГц до максимума карты %2$d МГц. Значение отправляется, когда вы отпускаете ползунок.",
        ocGfxTopFormat: "Максимум карты (%d МГц)",
        ocPowerLabel: "Лимит мощности выше значения загрузки",
        ocPowerHint: "Применяется при выборе, до потолка самой карты.",
        ocFooter: "Чтобы что-то выиграть, большей частоте обычно нужна большая мощность. Kext удерживает только одно за раз: лимит мощности и настройки частоты, вентилятора или напряжения никогда не удерживаются вместе. Выключение разгона возвращает всё, что он поднял.")

    static let sk = GPUControlOverclockStrings(
        voltSection: "Napätie GFX",
        voltFieldLabel: "Napätie GFX v mV",
        voltStepperFormat: "Napätie GFX, kroky po %d mV",
        voltToggle: "Znížiť napätie GFX",
        voltStockFormat: "Továrenské (%d mV)",
        voltSliderHelpFormat: "Od %1$d mV po továrenské napätie %2$d mV. Iba znižuje; hodnota sa odošle, keď ho prestanete posúvať.",
        voltOutOfRangeFormat: "Vyberte hodnotu od %1$d do %2$d mV v krokoch po %3$d mV od továrenskej.",
        voltRecommendedFormat: "Odporúčaný východiskový bod: %d mV. Východiskový bod na skúšanie, nie záruka.",
        voltUseRecommended: "Použiť východiskový bod",
        voltApply: "Použiť",
        voltFooter: "Zníži celú krivku napätia GPU o rozdiel oproti továrenskej hodnote: menej tepla a menšia spotreba. Ak je príliš nízko, GPU môže zamrznúť, reštartovať ovládač alebo ukázať čiernu obrazovku. Znižujte po 25 mV, skúšajte hrou alebo benchmarkom a zostaňte 10–20 mV nad najnižšou stabilnou hodnotou. Po ukončení RyzenStatus, reštarte a po spánku sa vráti na továrenskú hodnotu. Každý čip je iný.",
        ocSection: "Pretaktovanie",
        ocToggle: "Povoliť pretaktovanie",
        ocWarning: "V rámci limitov, ktoré AMD určuje pre túto kartu, nič nezhorí, ale hodnota môže byť nestabilná: GPU môže zamrznúť alebo reštartovať ovládač. Všetko sa vráti na továrenské hodnoty po vypnutí tejto voľby, po ukončení RyzenStatus, po reštarte a po spánku a strážca vráti továrenské hodnoty pri 95 °C.",
        ocGfxLabel: "Maximum GFX nad továrenskou hodnotou",
        ocGfxFieldLabel: "Zvýšený maximálny takt GFX v MHz",
        ocGfxStepperFormat: "Zvýšený maximálny takt GFX, kroky po %d MHz",
        ocGfxSliderHelpFormat: "Od továrenského maxima %1$d MHz po maximum karty %2$d MHz. Hodnota sa odošle, keď ho prestanete posúvať.",
        ocGfxTopFormat: "Maximum karty (%d MHz)",
        ocPowerLabel: "Limit príkonu nad štartovacou hodnotou",
        ocPowerHint: "Použije sa po výbere, až po strop samotnej karty.",
        ocFooter: "Vyšší takt zvyčajne potrebuje viac príkonu, aby niečo priniesol. Kext drží naraz len jednu vec: limit príkonu a nastavenia taktu, ventilátora alebo napätia sa nikdy nedržia spolu. Vypnutie pretaktovania vráti všetko, čo zvýšilo.")

    static let de = GPUControlOverclockStrings(
        voltSection: "GFX-Spannung",
        voltFieldLabel: "GFX-Spannung in mV",
        voltStepperFormat: "GFX-Spannung, Schritte von %d mV",
        voltToggle: "GFX-Spannung senken",
        voltStockFormat: "Werkswert (%d mV)",
        voltSliderHelpFormat: "Von %1$d mV bis zur Werksspannung, %2$d mV. Nur senken; der Wert wird gesendet, wenn du ihn loslässt.",
        voltOutOfRangeFormat: "Wähle einen Wert von %1$d bis %2$d mV, in Schritten von %3$d mV ab dem Werkswert.",
        voltRecommendedFormat: "Empfohlener Startpunkt: %d mV. Ein Startpunkt zum Testen, keine Garantie.",
        voltUseRecommended: "Startpunkt verwenden",
        voltApply: "Anwenden",
        voltFooter: "Senkt die ganze Spannungskurve der GPU um den Abstand zum Werkswert: weniger Wärme und weniger Verbrauch. Ist sie zu niedrig, kann die GPU einfrieren, ihren Treiber neu starten oder ein schwarzes Bild zeigen. Geh in Schritten von 25 mV nach unten, teste mit einem Spiel oder Benchmark und bleib 10–20 mV über dem niedrigsten stabilen Wert. Beim Beenden von RyzenStatus, beim Neustart und nach dem Ruhezustand geht sie auf den Werkswert zurück. Jeder Chip ist anders.",
        ocSection: "Übertakten",
        ocToggle: "Übertakten erlauben",
        ocWarning: "Innerhalb der Grenzen, die AMD für diese Karte selbst setzt, kann nichts durchbrennen, aber ein Wert kann instabil sein: Die GPU kann einfrieren oder ihren Treiber neu starten. Alles geht auf die Werkswerte zurück, wenn du das ausschaltest, wenn RyzenStatus beendet wird, beim Neustart und nach dem Ruhezustand, und der Wächter stellt bei 95 °C die Werkswerte wieder her.",
        ocGfxLabel: "GFX-Maximum über dem Werkswert",
        ocGfxFieldLabel: "Erhöhter maximaler GFX-Takt in MHz",
        ocGfxStepperFormat: "Erhöhter maximaler GFX-Takt, Schritte von %d MHz",
        ocGfxSliderHelpFormat: "Vom Werksmaximum, %1$d MHz, bis zum Maximum der Karte, %2$d MHz. Der Wert wird gesendet, wenn du ihn loslässt.",
        ocGfxTopFormat: "Kartenmaximum (%d MHz)",
        ocPowerLabel: "Leistungslimit über dem Startwert",
        ocPowerHint: "Gilt sofort nach der Auswahl, bis zur Obergrenze der Karte selbst.",
        ocFooter: "Mehr Takt braucht meist mehr Leistung, damit er etwas bringt. Der Kext hält immer nur eines: Ein Leistungslimit und Takt-, Lüfter- oder Spannungseinstellungen werden nie gleichzeitig gehalten. Wird Übertakten ausgeschaltet, geht alles zurück, was es erhöht hat.")

    static let fr = GPUControlOverclockStrings(
        voltSection: "Tension GFX",
        voltFieldLabel: "Tension GFX en mV",
        voltStepperFormat: "Tension GFX, pas de %d mV",
        voltToggle: "Baisser la tension GFX",
        voltStockFormat: "Usine (%d mV)",
        voltSliderHelpFormat: "De %1$d mV à la tension d’usine, %2$d mV. Ne fait que baisser ; la valeur est envoyée quand vous arrêtez de le déplacer.",
        voltOutOfRangeFormat: "Choisissez une valeur entre %1$d et %2$d mV, par pas de %3$d mV depuis la valeur d’usine.",
        voltRecommendedFormat: "Point de départ recommandé : %d mV. Un point de départ à tester, pas une garantie.",
        voltUseRecommended: "Utiliser le point de départ",
        voltApply: "Appliquer",
        voltFooter: "Baisse toute la courbe de tension du GPU de l’écart avec la valeur d’usine : moins de chaleur et moins de consommation. Trop basse, le GPU peut se figer, réinitialiser son pilote ou afficher un écran noir. Descendez de 25 mV à la fois, testez avec un jeu ou un benchmark et restez 10 à 20 mV au-dessus de la plus basse valeur restée stable. Elle revient à la valeur d’usine quand RyzenStatus quitte, au redémarrage et après la veille. Chaque puce est différente.",
        ocSection: "Overclocking",
        ocToggle: "Autoriser l’overclocking",
        ocWarning: "Dans les limites qu’AMD fixe pour cette carte, rien ne peut griller, mais une valeur peut être instable : le GPU peut se figer ou réinitialiser son pilote. Tout revient aux valeurs d’usine quand vous désactivez ceci, quand RyzenStatus quitte, au redémarrage et après la veille, et le gardien remet les valeurs d’usine à 95 °C.",
        ocGfxLabel: "Maximum GFX au-dessus de l’usine",
        ocGfxFieldLabel: "Fréquence GFX maximale relevée en MHz",
        ocGfxStepperFormat: "Fréquence GFX maximale relevée, pas de %d MHz",
        ocGfxSliderHelpFormat: "Du maximum d’usine, %1$d MHz, au maximum de la carte, %2$d MHz. La valeur est envoyée quand vous arrêtez de le déplacer.",
        ocGfxTopFormat: "Maximum de la carte (%d MHz)",
        ocPowerLabel: "Limite de puissance au-dessus du démarrage",
        ocPowerHint: "S’applique dès le choix, jusqu’au plafond de la carte elle-même.",
        ocFooter: "Plus de fréquence demande en général plus de puissance pour gagner quelque chose. Le kext ne maintient qu’une chose à la fois : une limite de puissance et des réglages de fréquence, de ventilateur ou de tension ne sont jamais maintenus ensemble. Désactiver l’overclocking remet tout ce qu’il a relevé.")

    static let it = GPUControlOverclockStrings(
        voltSection: "Tensione GFX",
        voltFieldLabel: "Tensione GFX in mV",
        voltStepperFormat: "Tensione GFX, passi di %d mV",
        voltToggle: "Abbassa la tensione GFX",
        voltStockFormat: "Di fabbrica (%d mV)",
        voltSliderHelpFormat: "Da %1$d mV alla tensione di fabbrica, %2$d mV. Solo abbassa; il valore viene inviato quando smetti di muoverlo.",
        voltOutOfRangeFormat: "Scegli un valore tra %1$d e %2$d mV, a passi di %3$d mV da quello di fabbrica.",
        voltRecommendedFormat: "Punto di partenza consigliato: %d mV. Un punto di partenza da provare, non una garanzia.",
        voltUseRecommended: "Usa punto di partenza",
        voltApply: "Applica",
        voltFooter: "Abbassa tutta la curva di tensione della GPU della differenza dal valore di fabbrica: meno calore e meno consumo. Se è troppo bassa, la GPU può bloccarsi, riavviare il driver o mostrare uno schermo nero. Scendi di 25 mV alla volta, prova con un gioco o un benchmark e resta 10–20 mV sopra il valore più basso rimasto stabile. Torna al valore di fabbrica quando RyzenStatus esce, al riavvio e dopo lo stop. Ogni chip è diverso.",
        ocSection: "Overclock",
        ocToggle: "Consenti l’overclock",
        ocWarning: "Entro i limiti che AMD stessa fissa per questa scheda non può bruciarsi nulla, ma un valore può essere instabile: la GPU può bloccarsi o riavviare il driver. Tutto torna ai valori di fabbrica quando lo disattivi, quando RyzenStatus esce, al riavvio e dopo lo stop, e il supervisore rimette i valori di fabbrica a 95 °C.",
        ocGfxLabel: "Massimo GFX sopra quello di fabbrica",
        ocGfxFieldLabel: "Clock GFX massimo alzato in MHz",
        ocGfxStepperFormat: "Clock GFX massimo alzato, passi di %d MHz",
        ocGfxSliderHelpFormat: "Dal massimo di fabbrica, %1$d MHz, al massimo della scheda, %2$d MHz. Il valore viene inviato quando smetti di muoverlo.",
        ocGfxTopFormat: "Massimo della scheda (%d MHz)",
        ocPowerLabel: "Limite di potenza sopra quello all’avvio",
        ocPowerHint: "Si applica appena scelto, fino al tetto della scheda stessa.",
        ocFooter: "Più clock di solito richiede più potenza per guadagnare qualcosa. Il kext mantiene una cosa alla volta: un limite di potenza e le impostazioni di clock, ventola o tensione non sono mai mantenuti insieme. Disattivare l’overclock rimette tutto ciò che aveva alzato.")

    static let ja = GPUControlOverclockStrings(
        voltSection: "GFX 電圧",
        voltFieldLabel: "GFX 電圧（mV）",
        voltStepperFormat: "GFX 電圧、%d mV 刻み",
        voltToggle: "GFX 電圧を下げる",
        voltStockFormat: "純正 (%d mV)",
        voltSliderHelpFormat: "%1$d mV から純正電圧 %2$d mV まで。下げるだけです。動かすのをやめると値が送られます。",
        voltOutOfRangeFormat: "%1$d〜%2$d mV の範囲で、純正から %3$d mV 刻みの値を選んでください。",
        voltRecommendedFormat: "推奨の出発点: %d mV。試すための出発点であり、保証ではありません。",
        voltUseRecommended: "出発点を使う",
        voltApply: "適用",
        voltFooter: "GPU の電圧カーブ全体を純正との差だけ下げます。発熱と消費電力が減ります。下げすぎると GPU がフリーズしたり、ドライバがリセットされたり、画面が真っ暗になったりします。25 mV ずつ下げてゲームやベンチマークで試し、安定した最低値より 10〜20 mV 上にとどめてください。RyzenStatus の終了時、再起動時、スリープ後に純正に戻ります。チップの個体差があります。",
        ocSection: "オーバークロック",
        ocToggle: "オーバークロックを許可",
        ocWarning: "AMD がこのカードに定めた範囲内なら壊れることはありませんが、値によっては不安定になり、GPU がフリーズしたりドライバがリセットされたりします。これをオフにしたとき、RyzenStatus の終了時、再起動時、スリープ後にはすべて純正に戻り、95 °C で監視が純正に戻します。",
        ocGfxLabel: "純正を超える GFX 最大クロック",
        ocGfxFieldLabel: "引き上げた GFX 最大クロック（MHz）",
        ocGfxStepperFormat: "引き上げた GFX 最大クロック、%d MHz 刻み",
        ocGfxSliderHelpFormat: "純正の最大 %1$d MHz からカードの最大 %2$d MHz まで。動かすのをやめると値が送られます。",
        ocGfxTopFormat: "カードの最大 (%d MHz)",
        ocPowerLabel: "起動時を超える電力制限",
        ocPowerHint: "選ぶとすぐに適用されます。カード自身の上限まで。",
        ocFooter: "クロックを上げて効果を得るには、通常より多くの電力が必要です。kext は一度に1つだけ保持します。電力制限とクロック、ファン、電圧の設定を同時に保持することはありません。オーバークロックをオフにすると、引き上げたものはすべて戻ります。")

    static let ko = GPUControlOverclockStrings(
        voltSection: "GFX 전압",
        voltFieldLabel: "GFX 전압(mV)",
        voltStepperFormat: "GFX 전압, %d mV 단위",
        voltToggle: "GFX 전압 낮추기",
        voltStockFormat: "기본값 (%d mV)",
        voltSliderHelpFormat: "%1$d mV부터 기본 전압 %2$d mV까지. 낮추기만 합니다. 움직임을 멈추면 값이 전송됩니다.",
        voltOutOfRangeFormat: "%1$d~%2$d mV 사이에서 기본값부터 %3$d mV 단위의 값을 고르세요.",
        voltRecommendedFormat: "권장 시작점: %d mV. 시험해 볼 시작점이며 보장은 아닙니다.",
        voltUseRecommended: "시작점 사용",
        voltApply: "적용",
        voltFooter: "GPU 전압 곡선 전체를 기본값과의 차이만큼 낮춥니다. 발열과 전력이 줄어듭니다. 너무 낮으면 GPU가 멈추거나, 드라이버가 재설정되거나, 화면이 검게 될 수 있습니다. 25 mV씩 낮추며 게임이나 벤치마크로 시험하고, 안정적이었던 가장 낮은 값보다 10~20 mV 위에 두세요. RyzenStatus를 종료할 때, 재시동할 때, 잠자기 후에는 기본값으로 돌아갑니다. 칩마다 차이가 있습니다.",
        ocSection: "오버클럭",
        ocToggle: "오버클럭 허용",
        ocWarning: "AMD가 이 카드에 정한 한도 안에서는 아무것도 타지 않지만, 값이 불안정할 수 있어 GPU가 멈추거나 드라이버가 재설정될 수 있습니다. 이 옵션을 끌 때, RyzenStatus를 종료할 때, 재시동할 때, 잠자기 후에는 모두 기본값으로 돌아가며, 95 °C에서는 감시가 기본값으로 되돌립니다.",
        ocGfxLabel: "기본값을 넘는 최대 GFX",
        ocGfxFieldLabel: "높인 최대 GFX 클록(MHz)",
        ocGfxStepperFormat: "높인 최대 GFX 클록, %d MHz 단위",
        ocGfxSliderHelpFormat: "기본 최대 %1$d MHz부터 카드 최대 %2$d MHz까지. 움직임을 멈추면 값이 전송됩니다.",
        ocGfxTopFormat: "카드 최대 (%d MHz)",
        ocPowerLabel: "시동 값을 넘는 전력 한도",
        ocPowerHint: "고르면 바로 적용되며, 카드 자체 상한까지입니다.",
        ocFooter: "클록을 높여 이득을 보려면 보통 더 많은 전력이 필요합니다. kext는 한 번에 하나만 유지합니다. 전력 한도와 클록, 팬 또는 전압 설정은 함께 유지되지 않습니다. 오버클럭을 끄면 높인 것은 모두 되돌아갑니다.")

    static let zhHans = GPUControlOverclockStrings(
        voltSection: "GFX 电压",
        voltFieldLabel: "GFX 电压（mV）",
        voltStepperFormat: "GFX 电压，步长 %d mV",
        voltToggle: "降低 GFX 电压",
        voltStockFormat: "出厂值（%d mV）",
        voltSliderHelpFormat: "从 %1$d mV 到出厂电压 %2$d mV。只会降低；停止拖动时发送数值。",
        voltOutOfRangeFormat: "请在 %1$d 到 %2$d mV 之间选择，从出厂值起以 %3$d mV 为步长。",
        voltRecommendedFormat: "推荐起点：%d mV。这是用来测试的起点，并非保证。",
        voltUseRecommended: "使用起点",
        voltApply: "应用",
        voltFooter: "将整条 GPU 电压曲线按与出厂值的差值降低：发热和功耗都会减少。过低时 GPU 可能卡死、重置驱动或黑屏。每次降低 25 mV，用游戏或基准测试检验，并保持比最低稳定值高 10–20 mV。退出 RyzenStatus、重新启动和睡眠后会恢复出厂值。每颗芯片都不一样。",
        ocSection: "超频",
        ocToggle: "允许超频",
        ocWarning: "在 AMD 为这张显卡设定的范围内不会烧坏任何东西，但某个数值可能不稳定：GPU 可能卡死或重置驱动。关闭此项时、退出 RyzenStatus、重新启动和睡眠后一切都会恢复出厂值，监控会在 95 °C 时恢复出厂值。",
        ocGfxLabel: "高于出厂值的 GFX 最大值",
        ocGfxFieldLabel: "提高后的 GFX 最大时钟频率（MHz）",
        ocGfxStepperFormat: "提高后的 GFX 最大时钟频率，步长 %d MHz",
        ocGfxSliderHelpFormat: "从出厂最大值 %1$d MHz 到显卡最大值 %2$d MHz。停止拖动时发送数值。",
        ocGfxTopFormat: "显卡最大值（%d MHz）",
        ocPowerLabel: "高于启动值的功率上限",
        ocPowerHint: "选择后立即应用，最高到显卡自身的上限。",
        ocFooter: "提高时钟频率通常需要更多功率才能有所收获。kext 一次只维持一项：功率上限与时钟频率、风扇或电压设置绝不会同时维持。关闭超频会恢复它提高的所有设置。")

    static let zhTW = GPUControlOverclockStrings(
        voltSection: "GFX 電壓",
        voltFieldLabel: "GFX 電壓（mV）",
        voltStepperFormat: "GFX 電壓，間隔 %d mV",
        voltToggle: "降低 GFX 電壓",
        voltStockFormat: "原廠值（%d mV）",
        voltSliderHelpFormat: "從 %1$d mV 到原廠電壓 %2$d mV。只會降低；停止拖動時送出數值。",
        voltOutOfRangeFormat: "請在 %1$d 到 %2$d mV 之間選擇，從原廠值起以 %3$d mV 為間隔。",
        voltRecommendedFormat: "建議起點：%d mV。這是用來測試的起點，並非保證。",
        voltUseRecommended: "使用起點",
        voltApply: "套用",
        voltFooter: "將整條 GPU 電壓曲線依與原廠值的差值降低：發熱與耗電都會減少。太低時 GPU 可能當機、重設驅動程式或黑畫面。每次降低 25 mV，用遊戲或基準測試檢驗，並保持比最低穩定值高 10–20 mV。結束 RyzenStatus、重新開機與睡眠後會恢復原廠值。每顆晶片都不一樣。",
        ocSection: "超頻",
        ocToggle: "允許超頻",
        ocWarning: "在 AMD 為這張顯示卡設定的範圍內不會燒壞任何東西，但某個數值可能不穩定：GPU 可能當機或重設驅動程式。關閉此項時、結束 RyzenStatus、重新開機與睡眠後一切都會恢復原廠值，監控會在 95 °C 時恢復原廠值。",
        ocGfxLabel: "高於原廠值的 GFX 最大值",
        ocGfxFieldLabel: "提高後的 GFX 最大時脈（MHz）",
        ocGfxStepperFormat: "提高後的 GFX 最大時脈，間隔 %d MHz",
        ocGfxSliderHelpFormat: "從原廠最大值 %1$d MHz 到顯示卡最大值 %2$d MHz。停止拖動時送出數值。",
        ocGfxTopFormat: "顯示卡最大值（%d MHz）",
        ocPowerLabel: "高於啟動值的功率上限",
        ocPowerHint: "選擇後立即套用，最高到顯示卡本身的上限。",
        ocFooter: "提高時脈通常需要更多功率才會有效果。kext 一次只維持一項：功率上限與時脈、風扇或電壓設定絕不會同時維持。關閉超頻會恢復它提高的所有設定。")

    static let uk = GPUControlOverclockStrings(
        voltSection: "Напруга GFX",
        voltFieldLabel: "Напруга GFX у мВ",
        voltStepperFormat: "Напруга GFX, крок %d мВ",
        voltToggle: "Знизити напругу GFX",
        voltStockFormat: "Заводська (%d мВ)",
        voltSliderHelpFormat: "Від %1$d мВ до заводської напруги %2$d мВ. Лише знижує; значення надсилається, коли ви відпускаєте повзунок.",
        voltOutOfRangeFormat: "Виберіть значення від %1$d до %2$d мВ із кроком %3$d мВ від заводського.",
        voltRecommendedFormat: "Рекомендована відправна точка: %d мВ. Це точка для перевірки, а не гарантія.",
        voltUseRecommended: "Узяти відправну точку",
        voltApply: "Застосувати",
        voltFooter: "Знижує всю криву напруги GPU на різницю із заводською: менше нагріву й споживання. Якщо надто низько, GPU може зависнути, перезапустити драйвер або показати чорний екран. Знижуйте по 25 мВ, перевіряйте грою чи бенчмарком і тримайтеся на 10–20 мВ вище найнижчого стабільного значення. Повертається до заводської після виходу з RyzenStatus, перезавантаження та сну. Кожен чип інший.",
        ocSection: "Розгін",
        ocToggle: "Дозволити розгін",
        ocWarning: "У межах, які AMD задає для цієї карти, нічого не згорить, але значення може бути нестабільним: GPU може зависнути або перезапустити драйвер. Усе повертається до заводського, коли ви вимикаєте це, після виходу з RyzenStatus, перезавантаження та сну, а сторож повертає заводські значення при 95 °C.",
        ocGfxLabel: "Макс. частота GFX вище заводської",
        ocGfxFieldLabel: "Підвищена макс. частота GFX у МГц",
        ocGfxStepperFormat: "Підвищена макс. частота GFX, крок %d МГц",
        ocGfxSliderHelpFormat: "Від заводського максимуму %1$d МГц до максимуму карти %2$d МГц. Значення надсилається, коли ви відпускаєте повзунок.",
        ocGfxTopFormat: "Максимум карти (%d МГц)",
        ocPowerLabel: "Ліміт потужності вище значення завантаження",
        ocPowerHint: "Застосовується під час вибору, до стелі самої карти.",
        ocFooter: "Щоб щось виграти, більшій частоті зазвичай потрібна більша потужність. Kext утримує лише одне за раз: ліміт потужності й налаштування частоти, вентилятора чи напруги ніколи не утримуються разом. Вимкнення розгону повертає все, що він підняв.")
}
