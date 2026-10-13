// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

struct NotchIslandExtrasStrings {
    let progressiveBlur: String
    let progressiveBlurHint: String
    let leaveAlert: String
    let leaveAlertHint: String
    let transport: String
    let car: String
    let walking: String
    let transit: String
    let timeToLeave: String
    /// A whole number of minutes, as `%d`.
    let travelMinutes: String
    let focus: String
    let focusHint: String
    let focusOn: String
    let focusOff: String
}

extension FeatureStrings {
    static func notchIslandExtras(_ language: AppLanguage) -> NotchIslandExtrasStrings {
        switch language {
        case .enUS: return NotchIslandExtrasStrings(
            progressiveBlur: "Blur behind the open island",
            progressiveBlurHint: "The top of the screen blurs and darkens behind the open Dynamic Island, fading out below it.",
            leaveAlert: "Time to leave",
            leaveAlertHint: "Before an event with a place, the Dynamic Island tells you when to set off, from the travel time there. Uses your location only for the route.",
            transport: "Getting there",
            car: "Driving", walking: "Walking", transit: "Transit",
            timeToLeave: "Time to leave", travelMinutes: "%d min",
            focus: "Focus",
            focusHint: "Shows when a Focus turns on or off.",
            focusOn: "On", focusOff: "Off")
        case .ptBR: return NotchIslandExtrasStrings(
            progressiveBlur: "Desfocar atrás da ilha aberta",
            progressiveBlurHint: "O topo da tela fica desfocado e mais escuro atrás do Dynamic Island aberto, sumindo abaixo dele.",
            leaveAlert: "Hora de sair",
            leaveAlertHint: "Antes de um evento com local, o Dynamic Island avisa quando sair, pelo tempo de viagem até lá. Usa sua localização só para a rota.",
            transport: "Como chegar",
            car: "De carro", walking: "A pé", transit: "Transporte público",
            timeToLeave: "Hora de sair", travelMinutes: "%d min",
            focus: "Foco",
            focusHint: "Mostra quando um modo Foco é ativado ou desativado.",
            focusOn: "Ativado", focusOff: "Desativado")
        case .es: return NotchIslandExtrasStrings(
            progressiveBlur: "Desenfocar detrás de la isla abierta",
            progressiveBlurHint: "La parte superior de la pantalla se desenfoca y oscurece detrás del Dynamic Island abierto y se desvanece por debajo.",
            leaveAlert: "Hora de salir",
            leaveAlertHint: "Antes de un evento con lugar, el Dynamic Island te avisa cuándo salir según el tiempo de trayecto. Usa tu ubicación solo para la ruta.",
            transport: "Cómo llegar",
            car: "En coche", walking: "A pie", transit: "Transporte público",
            timeToLeave: "Hora de salir", travelMinutes: "%d min",
            focus: "Concentración",
            focusHint: "Muestra cuándo se activa o desactiva un modo de concentración.",
            focusOn: "Activado", focusOff: "Desactivado")
        case .sk: return NotchIslandExtrasStrings(
            progressiveBlur: "Rozmazať za otvoreným ostrovom",
            progressiveBlurHint: "Horná časť obrazovky sa za otvoreným Dynamic Island rozmaže a stmavne a pod ním sa vytratí.",
            leaveAlert: "Čas vyraziť",
            leaveAlertHint: "Pred udalosťou s miestom vám Dynamic Island povie, kedy vyraziť, podľa času cesty. Polohu používa len na trasu.",
            transport: "Spôsob cesty",
            car: "Autom", walking: "Pešo", transit: "MHD",
            timeToLeave: "Čas vyraziť", travelMinutes: "%d min",
            focus: "Sústredenie",
            focusHint: "Zobrazí, keď sa režim sústredenia zapne alebo vypne.",
            focusOn: "Zapnuté", focusOff: "Vypnuté")
        case .de: return NotchIslandExtrasStrings(
            progressiveBlur: "Hinter geöffneter Insel weichzeichnen",
            progressiveBlurHint: "Der obere Bildschirmrand wird hinter dem geöffneten Dynamic Island weichgezeichnet und abgedunkelt und läuft darunter aus.",
            leaveAlert: "Zeit zum Aufbrechen",
            leaveAlertHint: "Vor einem Termin mit Ort sagt dir der Dynamic Island anhand der Fahrzeit, wann du losmusst. Dein Standort wird nur für die Route verwendet.",
            transport: "Anreise",
            car: "Mit dem Auto", walking: "Zu Fuß", transit: "ÖPNV",
            timeToLeave: "Zeit zum Aufbrechen", travelMinutes: "%d Min.",
            focus: "Fokus",
            focusHint: "Zeigt an, wenn ein Fokus ein- oder ausgeschaltet wird.",
            focusOn: "Ein", focusOff: "Aus")
        case .fr: return NotchIslandExtrasStrings(
            progressiveBlur: "Flouter derrière l’île ouverte",
            progressiveBlurHint: "Le haut de l’écran se floute et s’assombrit derrière le Dynamic Island ouvert, puis s’estompe en dessous.",
            leaveAlert: "Heure de partir",
            leaveAlertHint: "Avant un événement avec un lieu, le Dynamic Island vous indique quand partir d’après le temps de trajet. Votre position ne sert qu’à l’itinéraire.",
            transport: "Moyen de transport",
            car: "En voiture", walking: "À pied", transit: "Transports en commun",
            timeToLeave: "Heure de partir", travelMinutes: "%d min",
            focus: "Concentration",
            focusHint: "Indique quand un mode Concentration s’active ou se désactive.",
            focusOn: "Activé", focusOff: "Désactivé")
        case .it: return NotchIslandExtrasStrings(
            progressiveBlur: "Sfoca dietro l’isola aperta",
            progressiveBlurHint: "La parte superiore dello schermo si sfoca e si scurisce dietro il Dynamic Island aperto, sfumando sotto di esso.",
            leaveAlert: "Ora di partire",
            leaveAlertHint: "Prima di un evento con un luogo, il Dynamic Island ti dice quando partire in base al tempo di viaggio. La posizione serve solo per il percorso.",
            transport: "Come arrivare",
            car: "In auto", walking: "A piedi", transit: "Mezzi pubblici",
            timeToLeave: "Ora di partire", travelMinutes: "%d min",
            focus: "Full immersion",
            focusHint: "Mostra quando una modalità Full immersion si attiva o si disattiva.",
            focusOn: "Attiva", focusOff: "Disattivata")
        case .ru: return NotchIslandExtrasStrings(
            progressiveBlur: "Размытие за открытым островом",
            progressiveBlurHint: "Верх экрана размывается и затемняется за открытым Dynamic Island и плавно исчезает под ним.",
            leaveAlert: "Пора выходить",
            leaveAlertHint: "Перед событием с местом Dynamic Island подскажет, когда выходить, по времени в пути. Геопозиция используется только для маршрута.",
            transport: "Способ передвижения",
            car: "На машине", walking: "Пешком", transit: "Транспорт",
            timeToLeave: "Пора выходить", travelMinutes: "%d мин",
            focus: "Фокусирование",
            focusHint: "Показывает, когда режим фокусирования включается или выключается.",
            focusOn: "Вкл.", focusOff: "Выкл.")
        case .tr: return NotchIslandExtrasStrings(
            progressiveBlur: "Açık adanın arkasını bulanıklaştır",
            progressiveBlurHint: "Açık Dynamic Island’ın arkasında ekranın üstü bulanıklaşır ve kararır, altında giderek kaybolur.",
            leaveAlert: "Çıkma zamanı",
            leaveAlertHint: "Konumu olan bir etkinlikten önce Dynamic Island, yol süresine göre ne zaman çıkmanız gerektiğini söyler. Konumunuz yalnızca rota için kullanılır.",
            transport: "Ulaşım",
            car: "Araçla", walking: "Yürüyerek", transit: "Toplu taşıma",
            timeToLeave: "Çıkma zamanı", travelMinutes: "%d dk",
            focus: "Odak",
            focusHint: "Bir Odak modu açıldığında veya kapandığında gösterir.",
            focusOn: "Açık", focusOff: "Kapalı")
        case .ja: return NotchIslandExtrasStrings(
            progressiveBlur: "開いたアイランドの背後をぼかす",
            progressiveBlurHint: "開いたDynamic Islandの背後で画面上部がぼけて暗くなり、その下でフェードアウトします。",
            leaveAlert: "出発の時間",
            leaveAlertHint: "場所のある予定の前に、移動時間から出発すべき時刻をDynamic Islandが知らせます。位置情報は経路の計算にのみ使用します。",
            transport: "移動手段",
            car: "車", walking: "徒歩", transit: "公共交通機関",
            timeToLeave: "出発の時間", travelMinutes: "%d分",
            focus: "集中モード",
            focusHint: "集中モードのオン／オフを表示します。",
            focusOn: "オン", focusOff: "オフ")
        case .ko: return NotchIslandExtrasStrings(
            progressiveBlur: "열린 아일랜드 뒤 흐리게",
            progressiveBlurHint: "열린 Dynamic Island 뒤로 화면 상단이 흐려지고 어두워지며 그 아래에서 서서히 사라집니다.",
            leaveAlert: "출발 시간",
            leaveAlertHint: "장소가 있는 일정 전에 이동 시간에 맞춰 Dynamic Island가 출발할 때를 알려줍니다. 위치는 경로 계산에만 사용됩니다.",
            transport: "이동 수단",
            car: "자동차", walking: "도보", transit: "대중교통",
            timeToLeave: "출발 시간", travelMinutes: "%d분",
            focus: "집중 모드",
            focusHint: "집중 모드가 켜지거나 꺼질 때 표시합니다.",
            focusOn: "켬", focusOff: "끔")
        case .zhHans: return NotchIslandExtrasStrings(
            progressiveBlur: "模糊打开的灵动岛背后",
            progressiveBlurHint: "打开灵动岛时，屏幕顶部在其背后变得模糊并变暗，并在下方逐渐消失。",
            leaveAlert: "出发时间",
            leaveAlertHint: "在有地点的日程之前，灵动岛会根据路程时间提醒你何时出发。你的位置仅用于计算路线。",
            transport: "出行方式",
            car: "驾车", walking: "步行", transit: "公共交通",
            timeToLeave: "该出发了", travelMinutes: "%d 分钟",
            focus: "专注模式",
            focusHint: "在专注模式打开或关闭时显示。",
            focusOn: "已打开", focusOff: "已关闭")
        case .zhTW: return NotchIslandExtrasStrings(
            progressiveBlur: "模糊打開的動態島背後",
            progressiveBlurHint: "打開動態島時，螢幕頂部在其背後變得模糊並變暗，並在下方逐漸消失。",
            leaveAlert: "出發時間",
            leaveAlertHint: "在有地點的行程之前，動態島會依路程時間提醒你何時出發。你的位置僅用於計算路線。",
            transport: "交通方式",
            car: "開車", walking: "步行", transit: "大眾運輸",
            timeToLeave: "該出發了", travelMinutes: "%d 分鐘",
            focus: "專注模式",
            focusHint: "在專注模式開啟或關閉時顯示。",
            focusOn: "已開啟", focusOff: "已關閉")
        case .zhHK: return NotchIslandExtrasStrings(
            progressiveBlur: "模糊開啟的動態島背後",
            progressiveBlurHint: "開啟動態島時，螢幕頂部在其背後變得模糊並變暗，並在下方逐漸消失。",
            leaveAlert: "出發時間",
            leaveAlertHint: "在有地點的行程之前，動態島會按路程時間提醒你何時出發。你的位置只用於計算路線。",
            transport: "交通方式",
            car: "駕車", walking: "步行", transit: "公共交通",
            timeToLeave: "是時候出發", travelMinutes: "%d 分鐘",
            focus: "專注模式",
            focusHint: "在專注模式開啟或關閉時顯示。",
            focusOn: "已開啟", focusOff: "已關閉")
        case .uk: return NotchIslandExtrasStrings(
            progressiveBlur: "Розмиття за відкритим островом",
            progressiveBlurHint: "Верх екрана розмивається й темнішає за відкритим Dynamic Island і плавно зникає під ним.",
            leaveAlert: "Час виходити",
            leaveAlertHint: "Перед подією з місцем Dynamic Island підкаже, коли вирушати, за часом у дорозі. Геопозиція використовується лише для маршруту.",
            transport: "Спосіб пересування",
            car: "Автомобілем", walking: "Пішки", transit: "Громадський транспорт",
            timeToLeave: "Час виходити", travelMinutes: "%d хв",
            focus: "Зосередження",
            focusHint: "Показує, коли режим зосередження вмикається або вимикається.",
            focusOn: "Увімк.", focusOff: "Вимк.")
        }
    }
}
