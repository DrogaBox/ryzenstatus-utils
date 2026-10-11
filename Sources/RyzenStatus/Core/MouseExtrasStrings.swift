// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Strings for the mouse features ported from upstream: focus follows
/// mouse, sideways scrolling while holding a key, linear scrolling and
/// turning mouse acceleration off. Same contract as the other FeatureStrings
/// structs: memberwise init in declaration order, one static per language,
/// all in this file. Foundation-only, so the unit harness can name the
/// features through `AppFeature.hubTitle`.
struct MouseExtrasStrings {
    let focusFollowsMouseName: String
    let focusFollowsMouseCaption: String
    let focusFollowsMouseDelay: String
    let focusFollowsMouseRaise: String
    let focusFollowsMouseWaitForStop: String
    let scrollHorizontalName: String
    let scrollHorizontalCaption: String
    let scrollHorizontalModifierLabel: String
    let shiftKey: String
    let optionKey: String
    let controlKey: String
    let commandKey: String
    let linearScrollName: String
    let linearScrollCaption: String
    let linearScrollLinesLabel: String
    let mouseAccelerationName: String
    let mouseAccelerationCaption: String
}

extension FeatureStrings {
    static func mouseExtras(_ language: AppLanguage) -> MouseExtrasStrings {
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

extension MouseExtrasStrings {
    static let enUS = MouseExtrasStrings(
        focusFollowsMouseName: "Focus follows mouse",
        focusFollowsMouseCaption: "Focuses the window under the pointer.",
        focusFollowsMouseDelay: "Hover delay",
        focusFollowsMouseRaise: "Bring the window to the front",
        focusFollowsMouseWaitForStop: "Wait for the pointer to stop",
        scrollHorizontalName: "Scroll sideways while holding a key",
        scrollHorizontalCaption: "Hold only the selected modifier to scroll the vertical mouse wheel horizontally. Other key combinations are unchanged.",
        scrollHorizontalModifierLabel: "Modifier key",
        shiftKey: "Shift",
        optionKey: "Option",
        controlKey: "Control",
        commandKey: "Command",
        linearScrollName: "Linear scrolling",
        linearScrollCaption: "Every notch of the mouse wheel scrolls the same distance, no matter how fast it spins. The trackpad is not affected.",
        linearScrollLinesLabel: "Lines per step",
        mouseAccelerationName: "Disable mouse acceleration",
        mouseAccelerationCaption: "Removes pointer acceleration for connected mice. Your previous setting returns when this is turned off or RyzenStatus quits."
    )

    static let ptBR = MouseExtrasStrings(
        focusFollowsMouseName: "Foco ao passar o mouse",
        focusFollowsMouseCaption: "Coloca em foco a janela sob o ponteiro.",
        focusFollowsMouseDelay: "Atraso ao passar o mouse",
        focusFollowsMouseRaise: "Trazer a janela para frente",
        focusFollowsMouseWaitForStop: "Esperar o ponteiro parar",
        scrollHorizontalName: "Rolar na horizontal segurando uma tecla",
        scrollHorizontalCaption: "Mantenha apenas a tecla escolhida pressionada para rolar a roda vertical do mouse na horizontal. Outras combinações de teclas não são alteradas.",
        scrollHorizontalModifierLabel: "Tecla modificadora",
        shiftKey: "Shift",
        optionKey: "Option",
        controlKey: "Control",
        commandKey: "Command",
        linearScrollName: "Rolagem linear",
        linearScrollCaption: "Cada passo da rodinha do mouse rola a mesma distância, não importa a velocidade do giro. O trackpad não muda.",
        linearScrollLinesLabel: "Linhas por passo",
        mouseAccelerationName: "Desativar aceleração do mouse",
        mouseAccelerationCaption: "Remove a aceleração do cursor para os mouses conectados. A configuração anterior volta ao desligar esta opção ou sair do RyzenStatus."
    )

    static let tr = MouseExtrasStrings(
        focusFollowsMouseName: "Odak fareyi takip etsin",
        focusFollowsMouseCaption: "İşaretçinin altındaki pencereye odaklanır.",
        focusFollowsMouseDelay: "Üzerinde bekleme gecikmesi",
        focusFollowsMouseRaise: "Pencereyi öne getir",
        focusFollowsMouseWaitForStop: "İşaretçinin durmasını bekle",
        scrollHorizontalName: "Tuş basılıyken yatay kaydırma",
        scrollHorizontalCaption: "Dikey fare tekerleğiyle yatay kaydırmak için yalnızca seçilen değiştirici tuşu basılı tutun. Diğer tuş birleşimleri değişmez.",
        scrollHorizontalModifierLabel: "Değiştirici tuş",
        shiftKey: "Shift",
        optionKey: "Option",
        controlKey: "Control",
        commandKey: "Command",
        linearScrollName: "Doğrusal kaydırma",
        linearScrollCaption: "Fare tekerleğinin her adımı, ne kadar hızlı çevrilirse çevrilsin aynı mesafeyi kaydırır. İzleme dörtgeni değişmez.",
        linearScrollLinesLabel: "Adım başına satır",
        mouseAccelerationName: "Fare hızlandırmasını kapat",
        mouseAccelerationCaption: "Bağlı farelerde işaretçi hızlandırmasını kaldırır. Seçenek kapatıldığında veya RyzenStatus’ten çıkıldığında önceki ayar geri yüklenir."
    )

    static let ru = MouseExtrasStrings(
        focusFollowsMouseName: "Фокус следует за мышью",
        focusFollowsMouseCaption: "Фокусирует окно под указателем.",
        focusFollowsMouseDelay: "Задержка наведения",
        focusFollowsMouseRaise: "Поднимать окно на передний план",
        focusFollowsMouseWaitForStop: "Ждать, пока указатель остановится",
        scrollHorizontalName: "Горизонтальная прокрутка с зажатой клавишей",
        scrollHorizontalCaption: "Удерживайте только выбранную клавишу, чтобы вертикальное колёсико мыши прокручивало по горизонтали. Другие сочетания клавиш не изменяются.",
        scrollHorizontalModifierLabel: "Клавиша-модификатор",
        shiftKey: "Shift",
        optionKey: "Option",
        controlKey: "Control",
        commandKey: "Command",
        linearScrollName: "Линейная прокрутка",
        linearScrollCaption: "Каждый щелчок колёсика мыши прокручивает одно и то же расстояние независимо от скорости вращения. Трекпад не меняется.",
        linearScrollLinesLabel: "Строк на щелчок",
        mouseAccelerationName: "Отключить ускорение мыши",
        mouseAccelerationCaption: "Отключает ускорение указателя для подключённых мышей. Прежняя настройка вернётся после выключения функции или выхода из RyzenStatus."
    )

    static let es = MouseExtrasStrings(
        focusFollowsMouseName: "El foco sigue al ratón",
        focusFollowsMouseCaption: "Enfoca la ventana bajo el puntero.",
        focusFollowsMouseDelay: "Retraso al pasar",
        focusFollowsMouseRaise: "Traer la ventana al frente",
        focusFollowsMouseWaitForStop: "Esperar a que el puntero se detenga",
        scrollHorizontalName: "Desplazamiento horizontal al mantener una tecla",
        scrollHorizontalCaption: "Mantén pulsada solo la tecla elegida para desplazar horizontalmente con la rueda vertical del ratón. Las demás combinaciones de teclas no cambian.",
        scrollHorizontalModifierLabel: "Tecla modificadora",
        shiftKey: "Mayúsculas",
        optionKey: "Opción",
        controlKey: "Control",
        commandKey: "Comando",
        linearScrollName: "Desplazamiento lineal",
        linearScrollCaption: "Cada paso de la rueda del ratón desplaza la misma distancia, sin importar la velocidad del giro. El trackpad no cambia.",
        linearScrollLinesLabel: "Líneas por paso",
        mouseAccelerationName: "Desactivar la aceleración del ratón",
        mouseAccelerationCaption: "Elimina la aceleración del puntero para los ratones conectados. El ajuste anterior vuelve al desactivarlo o salir de RyzenStatus."
    )

    static let sk = MouseExtrasStrings(
        focusFollowsMouseName: "Zameranie sleduje myš",
        focusFollowsMouseCaption: "Zameria okno pod kurzorom.",
        focusFollowsMouseDelay: "Oneskorenie pri prejdení",
        focusFollowsMouseRaise: "Vyniesť okno dopredu",
        focusFollowsMouseWaitForStop: "Počkať, kým sa kurzor zastaví",
        scrollHorizontalName: "Rolovať do strán pri podržaní klávesu",
        scrollHorizontalCaption: "Podržaním samotného zvoleného modifikátora budete zvislým kolieskom myši rolovať vodorovne. Ostatné kombinácie klávesov ostávajú nezmenené.",
        scrollHorizontalModifierLabel: "Modifikačný kláves",
        shiftKey: "Shift",
        optionKey: "Option",
        controlKey: "Control",
        commandKey: "Command",
        linearScrollName: "Lineárne rolovanie",
        linearScrollCaption: "Každý krok kolieska myši posunie rovnakú vzdialenosť bez ohľadu na to, ako rýchlo sa točí. Trackpadu sa to netýka.",
        linearScrollLinesLabel: "Riadky na krok",
        mouseAccelerationName: "Vypnúť akceleráciu myši",
        mouseAccelerationCaption: "Odstráni akceleráciu kurzora pre pripojené myši. Predchádzajúce nastavenie sa vráti po vypnutí tejto funkcie alebo po ukončení RyzenStatusu."
    )

    static let de = MouseExtrasStrings(
        focusFollowsMouseName: "Fokus folgt Maus",
        focusFollowsMouseCaption: "Fokussiert das Fenster unter dem Zeiger.",
        focusFollowsMouseDelay: "Verzögerung",
        focusFollowsMouseRaise: "Fenster nach vorn bringen",
        focusFollowsMouseWaitForStop: "Warten, bis der Zeiger stillsteht",
        scrollHorizontalName: "Mit gedrückter Taste horizontal scrollen",
        scrollHorizontalCaption: "Halten Sie nur die gewählte Zusatztaste gedrückt, um mit dem vertikalen Mausrad horizontal zu scrollen. Andere Tastenkombinationen bleiben unverändert.",
        scrollHorizontalModifierLabel: "Zusatztaste",
        shiftKey: "Umschalttaste",
        optionKey: "Wahltaste",
        controlKey: "Control",
        commandKey: "Befehlstaste",
        linearScrollName: "Lineares Scrollen",
        linearScrollCaption: "Jeder Rastschritt des Mausrads scrollt dieselbe Strecke, egal wie schnell es gedreht wird. Das Trackpad bleibt unverändert.",
        linearScrollLinesLabel: "Zeilen pro Rastschritt",
        mouseAccelerationName: "Mausbeschleunigung deaktivieren",
        mouseAccelerationCaption: "Deaktiviert die Zeigerbeschleunigung für angeschlossene Mäuse. Die vorherige Einstellung wird beim Ausschalten oder Beenden von RyzenStatus wiederhergestellt."
    )

    static let fr = MouseExtrasStrings(
        focusFollowsMouseName: "Le focus suit la souris",
        focusFollowsMouseCaption: "Active la fenêtre sous le pointeur.",
        focusFollowsMouseDelay: "Délai de survol",
        focusFollowsMouseRaise: "Placer la fenêtre au premier plan",
        focusFollowsMouseWaitForStop: "Attendre que le pointeur s’arrête",
        scrollHorizontalName: "Défilement horizontal avec une touche",
        scrollHorizontalCaption: "Maintenez uniquement la touche choisie pour faire défiler horizontalement avec la molette verticale. Les autres combinaisons de touches restent inchangées.",
        scrollHorizontalModifierLabel: "Touche de modification",
        shiftKey: "Maj",
        optionKey: "Option",
        controlKey: "Contrôle",
        commandKey: "Commande",
        linearScrollName: "Défilement linéaire",
        linearScrollCaption: "Chaque cran de la molette de la souris fait défiler la même distance, quelle que soit la vitesse de rotation. Le trackpad ne change pas.",
        linearScrollLinesLabel: "Lignes par cran",
        mouseAccelerationName: "Désactiver l’accélération de la souris",
        mouseAccelerationCaption: "Supprime l’accélération du pointeur pour les souris connectées. Le réglage précédent est restauré à la désactivation ou à la fermeture de RyzenStatus."
    )

    static let it = MouseExtrasStrings(
        focusFollowsMouseName: "Il focus segue il mouse",
        focusFollowsMouseCaption: "Mette a fuoco la finestra sotto il puntatore.",
        focusFollowsMouseDelay: "Ritardo al passaggio",
        focusFollowsMouseRaise: "Porta la finestra in primo piano",
        focusFollowsMouseWaitForStop: "Attendi che il puntatore si fermi",
        scrollHorizontalName: "Scorrimento orizzontale tenendo premuto un tasto",
        scrollHorizontalCaption: "Tieni premuto solo il tasto scelto per scorrere in orizzontale con la rotellina verticale del mouse. Le altre combinazioni di tasti restano invariate.",
        scrollHorizontalModifierLabel: "Tasto modificatore",
        shiftKey: "Maiuscole",
        optionKey: "Opzione",
        controlKey: "Controllo",
        commandKey: "Comando",
        linearScrollName: "Scorrimento lineare",
        linearScrollCaption: "Ogni scatto della rotellina del mouse scorre la stessa distanza, a prescindere dalla velocità di rotazione. Il trackpad non cambia.",
        linearScrollLinesLabel: "Righe per scatto",
        mouseAccelerationName: "Disattiva l’accelerazione del mouse",
        mouseAccelerationCaption: "Rimuove l’accelerazione del puntatore per i mouse collegati. L’impostazione precedente viene ripristinata quando disattivi l’opzione o chiudi RyzenStatus."
    )

    static let ja = MouseExtrasStrings(
        focusFollowsMouseName: "マウス追従フォーカス",
        focusFollowsMouseCaption: "ポインタの下にあるウインドウをフォーカスします。",
        focusFollowsMouseDelay: "ホバー遅延",
        focusFollowsMouseRaise: "ウインドウを手前に表示",
        focusFollowsMouseWaitForStop: "ポインタが止まるまで待つ",
        scrollHorizontalName: "キーを押して横スクロール",
        scrollHorizontalCaption: "選択した修飾キーだけを押しながらマウスの縦ホイールを回すと、横にスクロールします。他のキーの組み合わせは変更しません。",
        scrollHorizontalModifierLabel: "修飾キー",
        shiftKey: "Shift",
        optionKey: "Option",
        controlKey: "Control",
        commandKey: "Command",
        linearScrollName: "リニアスクロール",
        linearScrollCaption: "マウスホイールの1目盛りで、回す速さに関係なく常に同じ距離をスクロールします。トラックパッドは変わりません。",
        linearScrollLinesLabel: "1目盛りあたりの行数",
        mouseAccelerationName: "マウス加速を無効にする",
        mouseAccelerationCaption: "接続したマウスのポインタ加速を無効にします。オフにするか RyzenStatus を終了すると以前の設定に戻ります。"
    )

    static let ko = MouseExtrasStrings(
        focusFollowsMouseName: "마우스를 따라 포커스",
        focusFollowsMouseCaption: "포인터 아래의 윈도우에 포커스를 줍니다.",
        focusFollowsMouseDelay: "호버 지연",
        focusFollowsMouseRaise: "윈도우를 앞으로 가져오기",
        focusFollowsMouseWaitForStop: "포인터가 멈출 때까지 기다리기",
        scrollHorizontalName: "키를 눌러 가로 스크롤",
        scrollHorizontalCaption: "선택한 보조 키만 누른 채 마우스 휠을 굴리면 가로로 스크롤합니다. 다른 키 조합은 변경하지 않습니다.",
        scrollHorizontalModifierLabel: "전환 키",
        shiftKey: "Shift",
        optionKey: "Option",
        controlKey: "Control",
        commandKey: "Command",
        linearScrollName: "선형 스크롤",
        linearScrollCaption: "마우스 휠을 얼마나 빨리 돌리든 한 칸마다 항상 같은 거리만큼 스크롤합니다. 트랙패드는 변경되지 않습니다.",
        linearScrollLinesLabel: "한 칸당 줄 수",
        mouseAccelerationName: "마우스 가속 끄기",
        mouseAccelerationCaption: "연결된 마우스의 포인터 가속을 끕니다. 옵션을 끄거나 RyzenStatus를 종료하면 이전 설정으로 복원됩니다."
    )

    static let zhHans = MouseExtrasStrings(
        focusFollowsMouseName: "悬停聚焦",
        focusFollowsMouseCaption: "聚焦指针下方的窗口。",
        focusFollowsMouseDelay: "悬停延迟",
        focusFollowsMouseRaise: "将窗口置前",
        focusFollowsMouseWaitForStop: "等待指针停下",
        scrollHorizontalName: "按住按键横向滚动",
        scrollHorizontalCaption: "仅按住所选修饰键，即可用鼠标的垂直滚轮进行水平滚动。其他组合键保持不变。",
        scrollHorizontalModifierLabel: "修饰键",
        shiftKey: "Shift",
        optionKey: "Option",
        controlKey: "Control",
        commandKey: "Command",
        linearScrollName: "线性滚动",
        linearScrollCaption: "无论转动多快，鼠标滚轮每一格都滚动相同的距离。触控板不受影响。",
        linearScrollLinesLabel: "每格行数",
        mouseAccelerationName: "关闭鼠标加速",
        mouseAccelerationCaption: "移除已连接鼠标的指针加速。关闭此选项或退出 RyzenStatus 后，会恢复之前的设置。"
    )

    static let zhTW = MouseExtrasStrings(
        focusFollowsMouseName: "游標停留時聚焦",
        focusFollowsMouseCaption: "聚焦游標下方的視窗。",
        focusFollowsMouseDelay: "停留延遲",
        focusFollowsMouseRaise: "將視窗移至最前方",
        focusFollowsMouseWaitForStop: "等待游標停下",
        scrollHorizontalName: "按住按鍵水平捲動",
        scrollHorizontalCaption: "僅按住所選輔助鍵，即可用滑鼠的垂直滾輪水平捲動。其他組合鍵維持不變。",
        scrollHorizontalModifierLabel: "輔助鍵",
        shiftKey: "Shift",
        optionKey: "Option",
        controlKey: "Control",
        commandKey: "Command",
        linearScrollName: "線性捲動",
        linearScrollCaption: "無論轉動多快，滑鼠滾輪每一格都捲動相同的距離。觸控式軌跡板不受影響。",
        linearScrollLinesLabel: "每格行數",
        mouseAccelerationName: "關閉滑鼠加速",
        mouseAccelerationCaption: "移除已連接滑鼠的指標加速。關閉此選項或結束 RyzenStatus 後，會還原先前的設定。"
    )

    static let zhHK = MouseExtrasStrings(
        focusFollowsMouseName: "游標停留時聚焦",
        focusFollowsMouseCaption: "聚焦游標下方的視窗。",
        focusFollowsMouseDelay: "停留延遲",
        focusFollowsMouseRaise: "將視窗移至最前方",
        focusFollowsMouseWaitForStop: "等待游標停下",
        scrollHorizontalName: "按住按鍵水平捲動",
        scrollHorizontalCaption: "只按住所選輔助鍵，即可用滑鼠的垂直滾輪水平捲動。其他組合鍵維持不變。",
        scrollHorizontalModifierLabel: "輔助鍵",
        shiftKey: "Shift",
        optionKey: "Option",
        controlKey: "Control",
        commandKey: "Command",
        linearScrollName: "線性捲動",
        linearScrollCaption: "無論轉動多快，滑鼠滾輪每一格都捲動相同的距離。觸控板不受影響。",
        linearScrollLinesLabel: "每格行數",
        mouseAccelerationName: "關閉滑鼠加速",
        mouseAccelerationCaption: "移除已連接滑鼠的指標加速。關閉此選項或結束 RyzenStatus 後，會還原之前的設定。"
    )

    static let uk = MouseExtrasStrings(
        focusFollowsMouseName: "Фокус за вказівником",
        focusFollowsMouseCaption: "Фокусує вікно під вказівником.",
        focusFollowsMouseDelay: "Затримка наведення",
        focusFollowsMouseRaise: "Піднімати вікно на передній план",
        focusFollowsMouseWaitForStop: "Чекати, поки вказівник зупиниться",
        scrollHorizontalName: "Прокручувати вбік під час утримання клавіші",
        scrollHorizontalCaption: "Тримайте лише обрану клавішу-модифікатор, щоб прокручувати вертикальне колесо миші горизонтально. Інші поєднання клавіш не змінюються.",
        scrollHorizontalModifierLabel: "Клавіша-модифікатор",
        shiftKey: "Shift",
        optionKey: "Option",
        controlKey: "Control",
        commandKey: "Command",
        linearScrollName: "Лінійна прокрутка",
        linearScrollCaption: "Кожен клац колеса миші прокручує однакову відстань, хоч як швидко воно обертається. Трекпед не змінюється.",
        linearScrollLinesLabel: "Рядків на клац",
        mouseAccelerationName: "Вимкнути прискорення миші",
        mouseAccelerationCaption: "Вимикає прискорення вказівника для підключених мишей. Попереднє налаштування повернеться після вимкнення функції або виходу з RyzenStatus."
    )
}
