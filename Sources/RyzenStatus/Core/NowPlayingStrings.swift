// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Strings for the Now Playing feature: its settings page and the menu panel
/// section. Same contract as the other FeatureStrings structs: memberwise
/// init with labeled arguments in declaration order, one static per language.
struct NowPlayingStrings {
    let pageTitle: String
    let hubDescription: String
    let menuBarModeLabel: String
    let menuBarModeIconOnly: String
    let menuBarModeArtist: String
    let menuBarModeSong: String
    let menuBarModeBoth: String
    let menuBarProgress: String
    let providerLabel: String
    let providerAuto: String
    let providerMusic: String
    let providerSpotify: String
    let openInAppToggle: String
    let openInAppCaption: String
    let artworkToggle: String
    let artworkAnimationToggle: String
    let emptyState: String
    let playLabel: String
    let pauseLabel: String
    let previousLabel: String
    let nextLabel: String
    let openInAppLabel: String
    let seekLabel: String
    let miniModeLabel: String
    let regularModeLabel: String
    let detachLabel: String
    let alwaysOnTopLabel: String
    let sizeLabel: String
    let sizeSmall: String
    let sizeMedium: String
    let sizeLarge: String
    let closeLabel: String
}

extension FeatureStrings {
    static func nowPlaying(_ language: AppLanguage) -> NowPlayingStrings {
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
        }
    }
}

extension NowPlayingStrings {
    static let enUS = NowPlayingStrings(
        pageTitle: "Now Playing",
        hubDescription: "Show the current track in the menu bar and the panel",
        menuBarModeLabel: "Menu bar text",
        menuBarModeIconOnly: "Icon only",
        menuBarModeArtist: "Artist",
        menuBarModeSong: "Song",
        menuBarModeBoth: "Artist + Song",
        menuBarProgress: "Progress bar in menu bar",
        providerLabel: "Preferred provider",
        providerAuto: "Auto",
        providerMusic: "Apple Music",
        providerSpotify: "Spotify",
        openInAppToggle: "Open source app on click",
        openInAppCaption: "Click the track title to jump to the app playing it",
        artworkToggle: "Show artwork",
        artworkAnimationToggle: "Animate artwork",
        emptyState: "Nothing playing",
        playLabel: "Play",
        pauseLabel: "Pause",
        previousLabel: "Previous track",
        nextLabel: "Next track",
        openInAppLabel: "Open in App",
        seekLabel: "Seek",
        miniModeLabel: "Mini mode",
        regularModeLabel: "Regular mode",
        detachLabel: "Detach to window",
        alwaysOnTopLabel: "Always on top",
        sizeLabel: "Size",
        sizeSmall: "Small",
        sizeMedium: "Medium",
        sizeLarge: "Large",
        closeLabel: "Close"
    )

    static let ptBR = NowPlayingStrings(
        pageTitle: "Em reprodução",
        hubDescription: "Mostra a faixa atual na barra de menus e no painel",
        menuBarModeLabel: "Texto da barra de menus",
        menuBarModeIconOnly: "Somente ícone",
        menuBarModeArtist: "Artista",
        menuBarModeSong: "Faixa",
        menuBarModeBoth: "Artista + Faixa",
        menuBarProgress: "Barra de progresso na barra de menus",
        providerLabel: "Provedor preferido",
        providerAuto: "Automático",
        providerMusic: "Apple Music",
        providerSpotify: "Spotify",
        openInAppToggle: "Abrir o app de origem ao clicar",
        openInAppCaption: "Clique no título da faixa para ir ao app que a reproduz",
        artworkToggle: "Mostrar capa",
        artworkAnimationToggle: "Animar capa",
        emptyState: "Nada em reprodução",
        playLabel: "Reproduzir",
        pauseLabel: "Pausar",
        previousLabel: "Faixa anterior",
        nextLabel: "Próxima faixa",
        openInAppLabel: "Abrir no app",
        seekLabel: "Buscar",
        miniModeLabel: "Modo mini",
        regularModeLabel: "Modo normal",
        detachLabel: "Destacar em janela",
        alwaysOnTopLabel: "Sempre no topo",
        sizeLabel: "Tamanho",
        sizeSmall: "Pequeno",
        sizeMedium: "Médio",
        sizeLarge: "Grande",
        closeLabel: "Fechar"
    )

    static let tr = NowPlayingStrings(
        pageTitle: "Çalınan",
        hubDescription: "Çalan parçayı menü çubuğunda ve panelde göster",
        menuBarModeLabel: "Menü çubuğu metni",
        menuBarModeIconOnly: "Sadece simge",
        menuBarModeArtist: "Sanatçı",
        menuBarModeSong: "Parça",
        menuBarModeBoth: "Sanatçı + Parça",
        menuBarProgress: "Menü çubuğunda ilerleme çubuğu",
        providerLabel: "Tercih edilen sağlayıcı",
        providerAuto: "Otomatik",
        providerMusic: "Apple Music",
        providerSpotify: "Spotify",
        openInAppToggle: "Tıklayınca kaynak uygulamayı aç",
        openInAppCaption: "Parça başlığına tıklayarak onu çalan uygulamaya geç",
        artworkToggle: "Kapak resmini göster",
        artworkAnimationToggle: "Kapak animasyonu",
        emptyState: "Çalan bir şey yok",
        playLabel: "Çal",
        pauseLabel: "Duraklat",
        previousLabel: "Önceki parça",
        nextLabel: "Sonraki parça",
        openInAppLabel: "Uygulamada aç",
        seekLabel: "İlerlet",
        miniModeLabel: "Mini mod",
        regularModeLabel: "Normal mod",
        detachLabel: "Pencereye ayır",
        alwaysOnTopLabel: "Her zaman üstte",
        sizeLabel: "Boyut",
        sizeSmall: "Küçük",
        sizeMedium: "Orta",
        sizeLarge: "Büyük",
        closeLabel: "Kapat"
    )

    static let ru = NowPlayingStrings(
        pageTitle: "Сейчас играет",
        hubDescription: "Показывает текущий трек в строке меню и панели",
        menuBarModeLabel: "Текст в строке меню",
        menuBarModeIconOnly: "Только значок",
        menuBarModeArtist: "Исполнитель",
        menuBarModeSong: "Трек",
        menuBarModeBoth: "Исполнитель + трек",
        menuBarProgress: "Полоса прогресса в строке меню",
        providerLabel: "Предпочитаемый источник",
        providerAuto: "Авто",
        providerMusic: "Apple Music",
        providerSpotify: "Spotify",
        openInAppToggle: "Открывать исходное приложение по клику",
        openInAppCaption: "Нажмите на название трека, чтобы перейти к приложению, в котором он играет",
        artworkToggle: "Показывать обложку",
        artworkAnimationToggle: "Анимация обложки",
        emptyState: "Ничего не играет",
        playLabel: "Играть",
        pauseLabel: "Пауза",
        previousLabel: "Предыдущий трек",
        nextLabel: "Следующий трек",
        openInAppLabel: "Открыть в приложении",
        seekLabel: "Перемотка",
        miniModeLabel: "Мини-режим",
        regularModeLabel: "Обычный режим",
        detachLabel: "Открепить в окно",
        alwaysOnTopLabel: "Поверх всех окон",
        sizeLabel: "Размер",
        sizeSmall: "Маленький",
        sizeMedium: "Средний",
        sizeLarge: "Большой",
        closeLabel: "Закрыть"
    )

    static let es = NowPlayingStrings(
        pageTitle: "En reproducción",
        hubDescription: "Muestra la canción actual en la barra de menús y el panel",
        menuBarModeLabel: "Texto de la barra de menús",
        menuBarModeIconOnly: "Solo icono",
        menuBarModeArtist: "Artista",
        menuBarModeSong: "Canción",
        menuBarModeBoth: "Artista + Canción",
        menuBarProgress: "Barra de progreso en la barra de menús",
        providerLabel: "Proveedor preferido",
        providerAuto: "Automático",
        providerMusic: "Apple Music",
        providerSpotify: "Spotify",
        openInAppToggle: "Abrir la app de origen al hacer clic",
        openInAppCaption: "Haz clic en el título de la canción para ir a la app que la reproduce",
        artworkToggle: "Mostrar carátula",
        artworkAnimationToggle: "Animar carátula",
        emptyState: "No hay nada en reproducción",
        playLabel: "Reproducir",
        pauseLabel: "Pausa",
        previousLabel: "Canción anterior",
        nextLabel: "Canción siguiente",
        openInAppLabel: "Abrir en la app",
        seekLabel: "Buscar",
        miniModeLabel: "Modo mini",
        regularModeLabel: "Modo normal",
        detachLabel: "Separar en ventana",
        alwaysOnTopLabel: "Siempre encima",
        sizeLabel: "Tamaño",
        sizeSmall: "Pequeño",
        sizeMedium: "Mediano",
        sizeLarge: "Grande",
        closeLabel: "Cerrar"
    )

    static let de = NowPlayingStrings(
        pageTitle: "Aktueller Titel",
        hubDescription: "Zeigt den aktuellen Titel in der Menüleiste und im Panel an",
        menuBarModeLabel: "Menüleistentext",
        menuBarModeIconOnly: "Nur Symbol",
        menuBarModeArtist: "Künstler",
        menuBarModeSong: "Titel",
        menuBarModeBoth: "Künstler + Titel",
        menuBarProgress: "Fortschrittsbalken in der Menüleiste",
        providerLabel: "Bevorzugter Anbieter",
        providerAuto: "Automatisch",
        providerMusic: "Apple Music",
        providerSpotify: "Spotify",
        openInAppToggle: "Quell-App bei Klick öffnen",
        openInAppCaption: "Klicke auf den Titel, um zur App zu springen, die ihn abspielt",
        artworkToggle: "Cover anzeigen",
        artworkAnimationToggle: "Cover animieren",
        emptyState: "Nichts wird abgespielt",
        playLabel: "Abspielen",
        pauseLabel: "Pause",
        previousLabel: "Vorheriger Titel",
        nextLabel: "Nächster Titel",
        openInAppLabel: "In App öffnen",
        seekLabel: "Springen",
        miniModeLabel: "Mini-Modus",
        regularModeLabel: "Normaler Modus",
        detachLabel: "In Fenster lösen",
        alwaysOnTopLabel: "Immer im Vordergrund",
        sizeLabel: "Größe",
        sizeSmall: "Klein",
        sizeMedium: "Mittel",
        sizeLarge: "Groß",
        closeLabel: "Schließen"
    )

    static let fr = NowPlayingStrings(
        pageTitle: "En cours de lecture",
        hubDescription: "Affiche le morceau en cours dans la barre des menus et le panneau",
        menuBarModeLabel: "Texte de la barre des menus",
        menuBarModeIconOnly: "Icône uniquement",
        menuBarModeArtist: "Artiste",
        menuBarModeSong: "Morceau",
        menuBarModeBoth: "Artiste + Morceau",
        menuBarProgress: "Barre de progression dans la barre des menus",
        providerLabel: "Fournisseur préféré",
        providerAuto: "Automatique",
        providerMusic: "Apple Music",
        providerSpotify: "Spotify",
        openInAppToggle: "Ouvrir l'app source au clic",
        openInAppCaption: "Cliquez sur le titre du morceau pour accéder à l'app qui le diffuse",
        artworkToggle: "Afficher la pochette",
        artworkAnimationToggle: "Animer la pochette",
        emptyState: "Rien en cours de lecture",
        playLabel: "Lire",
        pauseLabel: "Pause",
        previousLabel: "Morceau précédent",
        nextLabel: "Morceau suivant",
        openInAppLabel: "Ouvrir dans l'app",
        seekLabel: "Rechercher",
        miniModeLabel: "Mode mini",
        regularModeLabel: "Mode normal",
        detachLabel: "Détacher dans une fenêtre",
        alwaysOnTopLabel: "Toujours au premier plan",
        sizeLabel: "Taille",
        sizeSmall: "Petit",
        sizeMedium: "Moyen",
        sizeLarge: "Grand",
        closeLabel: "Fermer"
    )

    static let it = NowPlayingStrings(
        pageTitle: "In riproduzione",
        hubDescription: "Mostra il brano in corso nella barra dei menu e nel pannello",
        menuBarModeLabel: "Testo della barra dei menu",
        menuBarModeIconOnly: "Solo icona",
        menuBarModeArtist: "Artista",
        menuBarModeSong: "Brano",
        menuBarModeBoth: "Artista + Brano",
        menuBarProgress: "Barra di avanzamento nella barra dei menu",
        providerLabel: "Provider preferito",
        providerAuto: "Automatico",
        providerMusic: "Apple Music",
        providerSpotify: "Spotify",
        openInAppToggle: "Apri l'app di origine al clic",
        openInAppCaption: "Fai clic sul titolo del brano per passare all'app che lo riproduce",
        artworkToggle: "Mostra copertina",
        artworkAnimationToggle: "Anima copertina",
        emptyState: "Niente in riproduzione",
        playLabel: "Riproduci",
        pauseLabel: "Pausa",
        previousLabel: "Brano precedente",
        nextLabel: "Brano successivo",
        openInAppLabel: "Apri nell'app",
        seekLabel: "Cerca",
        miniModeLabel: "Modalità mini",
        regularModeLabel: "Modalità normale",
        detachLabel: "Separa in finestra",
        alwaysOnTopLabel: "Sempre in primo piano",
        sizeLabel: "Dimensione",
        sizeSmall: "Piccolo",
        sizeMedium: "Medio",
        sizeLarge: "Grande",
        closeLabel: "Chiudi"
    )

    static let ja = NowPlayingStrings(
        pageTitle: "再生中",
        hubDescription: "現在の曲をメニューバーとパネルに表示",
        menuBarModeLabel: "メニューバーのテキスト",
        menuBarModeIconOnly: "アイコンのみ",
        menuBarModeArtist: "アーティスト",
        menuBarModeSong: "曲名",
        menuBarModeBoth: "アーティスト + 曲名",
        menuBarProgress: "メニューバーにプログレスバー",
        providerLabel: "優先プロバイダ",
        providerAuto: "自動",
        providerMusic: "Apple Music",
        providerSpotify: "Spotify",
        openInAppToggle: "クリックで再生元アプリを開く",
        openInAppCaption: "曲名をクリックすると再生中のアプリに移動します",
        artworkToggle: "アートワークを表示",
        artworkAnimationToggle: "アートワークをアニメーション化",
        emptyState: "再生中の曲はありません",
        playLabel: "再生",
        pauseLabel: "一時停止",
        previousLabel: "前の曲",
        nextLabel: "次の曲",
        openInAppLabel: "アプリで開く",
        seekLabel: "シーク",
        miniModeLabel: "ミニモード",
        regularModeLabel: "通常モード",
        detachLabel: "ウィンドウとして切り離す",
        alwaysOnTopLabel: "常に手前に表示",
        sizeLabel: "サイズ",
        sizeSmall: "小",
        sizeMedium: "中",
        sizeLarge: "大",
        closeLabel: "閉じる"
    )

    static let ko = NowPlayingStrings(
        pageTitle: "재생 중",
        hubDescription: "현재 재생 중인 곡을 메뉴 막대와 패널에 표시",
        menuBarModeLabel: "메뉴 막대 텍스트",
        menuBarModeIconOnly: "아이콘만",
        menuBarModeArtist: "아티스트",
        menuBarModeSong: "곡",
        menuBarModeBoth: "아티스트 + 곡",
        menuBarProgress: "메뉴 막대에 진행 막대",
        providerLabel: "선호 공급자",
        providerAuto: "자동",
        providerMusic: "Apple Music",
        providerSpotify: "Spotify",
        openInAppToggle: "클릭하면 원본 앱 열기",
        openInAppCaption: "곡 제목을 클릭하면 재생 중인 앱으로 이동합니다",
        artworkToggle: "아트워크 표시",
        artworkAnimationToggle: "아트워크 애니메이션",
        emptyState: "재생 중인 곡 없음",
        playLabel: "재생",
        pauseLabel: "일시 정지",
        previousLabel: "이전 곡",
        nextLabel: "다음 곡",
        openInAppLabel: "앱에서 열기",
        seekLabel: "탐색",
        miniModeLabel: "미니 모드",
        regularModeLabel: "일반 모드",
        detachLabel: "창으로 분리",
        alwaysOnTopLabel: "항상 위에",
        sizeLabel: "크기",
        sizeSmall: "작게",
        sizeMedium: "보통",
        sizeLarge: "크게",
        closeLabel: "닫기"
    )

    static let zhHans = NowPlayingStrings(
        pageTitle: "正在播放",
        hubDescription: "在菜单栏和面板中显示当前曲目",
        menuBarModeLabel: "菜单栏文本",
        menuBarModeIconOnly: "仅图标",
        menuBarModeArtist: "艺术家",
        menuBarModeSong: "歌曲",
        menuBarModeBoth: "艺术家 + 歌曲",
        menuBarProgress: "菜单栏中的进度条",
        providerLabel: "首选来源",
        providerAuto: "自动",
        providerMusic: "Apple Music",
        providerSpotify: "Spotify",
        openInAppToggle: "点击时打开来源应用",
        openInAppCaption: "点击歌曲标题可跳转到正在播放它的应用",
        artworkToggle: "显示封面",
        artworkAnimationToggle: "封面过渡动画",
        emptyState: "没有正在播放的内容",
        playLabel: "播放",
        pauseLabel: "暂停",
        previousLabel: "上一首",
        nextLabel: "下一首",
        openInAppLabel: "在应用中打开",
        seekLabel: "跳转",
        miniModeLabel: "迷你模式",
        regularModeLabel: "常规模式",
        detachLabel: "分离为窗口",
        alwaysOnTopLabel: "始终置顶",
        sizeLabel: "大小",
        sizeSmall: "小",
        sizeMedium: "中",
        sizeLarge: "大",
        closeLabel: "关闭"
    )

    static let zhTW = NowPlayingStrings(
        pageTitle: "正在播放",
        hubDescription: "在選單列和面板中顯示目前曲目",
        menuBarModeLabel: "選單列文字",
        menuBarModeIconOnly: "僅圖示",
        menuBarModeArtist: "藝人",
        menuBarModeSong: "歌曲",
        menuBarModeBoth: "藝人 + 歌曲",
        menuBarProgress: "選單列中的進度列",
        providerLabel: "偏好的來源",
        providerAuto: "自動",
        providerMusic: "Apple Music",
        providerSpotify: "Spotify",
        openInAppToggle: "點按時開啟來源 App",
        openInAppCaption: "點按歌曲標題即可跳至播放它的 App",
        artworkToggle: "顯示封面",
        artworkAnimationToggle: "封面過場動畫",
        emptyState: "沒有正在播放的內容",
        playLabel: "播放",
        pauseLabel: "暫停",
        previousLabel: "上一首",
        nextLabel: "下一首",
        openInAppLabel: "在 App 中開啟",
        seekLabel: "跳轉",
        miniModeLabel: "迷你模式",
        regularModeLabel: "一般模式",
        detachLabel: "分離為視窗",
        alwaysOnTopLabel: "永遠置頂",
        sizeLabel: "大小",
        sizeSmall: "小",
        sizeMedium: "中",
        sizeLarge: "大",
        closeLabel: "關閉"
    )

    static let zhHK = NowPlayingStrings(
        pageTitle: "正在播放",
        hubDescription: "喺選單列同面板度顯示目前曲目",
        menuBarModeLabel: "選單列文字",
        menuBarModeIconOnly: "淨係圖示",
        menuBarModeArtist: "藝人",
        menuBarModeSong: "歌曲",
        menuBarModeBoth: "藝人 + 歌曲",
        menuBarProgress: "選單列入面嘅進度列",
        providerLabel: "偏好來源",
        providerAuto: "自動",
        providerMusic: "Apple Music",
        providerSpotify: "Spotify",
        openInAppToggle: "㩒嘅時候開啟來源 App",
        openInAppCaption: "㩒歌曲標題就可以跳去播放緊嘅 App",
        artworkToggle: "顯示封面",
        artworkAnimationToggle: "封面過場動畫",
        emptyState: "而家冇嘢播",
        playLabel: "播放",
        pauseLabel: "暫停",
        previousLabel: "上一首",
        nextLabel: "下一首",
        openInAppLabel: "喺 App 度開啟",
        seekLabel: "跳轉",
        miniModeLabel: "迷你模式",
        regularModeLabel: "一般模式",
        detachLabel: "分離做視窗",
        alwaysOnTopLabel: "永遠置頂",
        sizeLabel: "大細",
        sizeSmall: "細",
        sizeMedium: "中",
        sizeLarge: "大",
        closeLabel: "關閉"
    )
}
