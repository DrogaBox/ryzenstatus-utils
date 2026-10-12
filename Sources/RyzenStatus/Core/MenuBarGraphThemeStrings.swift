// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

struct MenuBarGraphThemeStrings {
    let title: String
    let lightMode: String
    let darkMode: String
    let system: String
    let mono: String
    let blue: String
    let green: String
    let aqua: String
    let red: String
    let purple: String
    let indigo: String
    let yellow: String
    let pink: String
    let orange: String
    let graphite: String
    /// A muted variant; `%@` is one of the color names above.
    let softFormat: String
    let lightBackground: String
    let backgroundFilled: String
    let backgroundOutline: String
    let historyWidth: String
    let widthNarrow: String
    let widthStandard: String
    let widthWide: String
    let spacedColumns: String
    let networkLayout: String
    let networkMirrored: String
    let networkSplit: String
    let networkRising: String
    let caption: String

    func name(of theme: MenuBarGraphTheme) -> String {
        switch theme {
        case .system: return system
        case .mono: return mono
        case .blue: return blue
        case .green: return green
        case .aqua: return aqua
        case .red: return red
        case .purple: return purple
        case .indigo: return indigo
        case .yellow: return yellow
        case .pink: return pink
        case .orange: return orange
        case .graphite: return graphite
        case .softYellow: return String(format: softFormat, yellow)
        case .softGreen: return String(format: softFormat, green)
        case .softBlue: return String(format: softFormat, blue)
        case .softPink: return String(format: softFormat, pink)
        case .softPurple: return String(format: softFormat, purple)
        case .softOrange: return String(format: softFormat, orange)
        }
    }
}

extension FeatureStrings {
    static func menuBarGraphTheme(_ language: AppLanguage) -> MenuBarGraphThemeStrings {
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

extension MenuBarGraphThemeStrings {
    static let enUS = MenuBarGraphThemeStrings(
        title: "Graph theme",
        lightMode: "Light menu bar",
        darkMode: "Dark menu bar",
        system: "System accent",
        mono: "Monochrome",
        blue: "Blue",
        green: "Green",
        aqua: "Aqua",
        red: "Red",
        purple: "Purple",
        indigo: "Indigo",
        yellow: "Yellow",
        pink: "Pink",
        orange: "Orange",
        graphite: "Graphite",
        softFormat: "Soft %@",
        lightBackground: "Background on a light menu bar",
        backgroundFilled: "Dark",
        backgroundOutline: "Outline",
        historyWidth: "History width",
        widthNarrow: "Narrow",
        widthStandard: "Standard",
        widthWide: "Wide",
        spacedColumns: "Space out history columns",
        networkLayout: "Network graph",
        networkMirrored: "Mirrored",
        networkSplit: "Top and bottom",
        networkRising: "Both rising",
        caption: "Graphs draw in the theme's main color. CPU system time, upload and the rest of used memory use its second color."
    )

    static let ptBR = MenuBarGraphThemeStrings(
        title: "Tema dos gráficos",
        lightMode: "Barra de menus clara",
        darkMode: "Barra de menus escura",
        system: "Destaque do sistema",
        mono: "Monocromático",
        blue: "Azul",
        green: "Verde",
        aqua: "Água",
        red: "Vermelho",
        purple: "Roxo",
        indigo: "Índigo",
        yellow: "Amarelo",
        pink: "Rosa",
        orange: "Laranja",
        graphite: "Grafite",
        softFormat: "%@ suave",
        lightBackground: "Fundo com a barra clara",
        backgroundFilled: "Escuro",
        backgroundOutline: "Contorno",
        historyWidth: "Largura do histórico",
        widthNarrow: "Estreita",
        widthStandard: "Padrão",
        widthWide: "Larga",
        spacedColumns: "Espaçar as colunas do histórico",
        networkLayout: "Gráfico de rede",
        networkMirrored: "Espelhado",
        networkSplit: "Em cima e embaixo",
        networkRising: "Ambos para cima",
        caption: "Os gráficos usam a cor principal do tema. O tempo de sistema da CPU, o envio e o restante da memória usada usam a segunda cor."
    )

    static let tr = MenuBarGraphThemeStrings(
        title: "Grafik teması",
        lightMode: "Açık menü çubuğu",
        darkMode: "Koyu menü çubuğu",
        system: "Sistem vurgu rengi",
        mono: "Tek renk",
        blue: "Mavi",
        green: "Yeşil",
        aqua: "Turkuaz",
        red: "Kırmızı",
        purple: "Mor",
        indigo: "Çivit",
        yellow: "Sarı",
        pink: "Pembe",
        orange: "Turuncu",
        graphite: "Grafit",
        softFormat: "Yumuşak %@",
        lightBackground: "Açık çubukta arka plan",
        backgroundFilled: "Koyu",
        backgroundOutline: "Çerçeve",
        historyWidth: "Geçmiş genişliği",
        widthNarrow: "Dar",
        widthStandard: "Standart",
        widthWide: "Geniş",
        spacedColumns: "Geçmiş sütunlarını aralıklı çiz",
        networkLayout: "Ağ grafiği",
        networkMirrored: "Ayna",
        networkSplit: "Üstte ve altta",
        networkRising: "İkisi de yukarı",
        caption: "Grafikler temanın ana rengini kullanır. CPU sistem süresi, yükleme ve kullanılan belleğin geri kalanı ikinci rengi kullanır."
    )

    static let ru = MenuBarGraphThemeStrings(
        title: "Тема графиков",
        lightMode: "Светлая строка меню",
        darkMode: "Тёмная строка меню",
        system: "Акцент системы",
        mono: "Монохром",
        blue: "Синий",
        green: "Зелёный",
        aqua: "Бирюзовый",
        red: "Красный",
        purple: "Фиолетовый",
        indigo: "Индиго",
        yellow: "Жёлтый",
        pink: "Розовый",
        orange: "Оранжевый",
        graphite: "Графит",
        softFormat: "%@ (приглушённый)",
        lightBackground: "Фон в светлой строке меню",
        backgroundFilled: "Тёмный",
        backgroundOutline: "Контур",
        historyWidth: "Ширина истории",
        widthNarrow: "Узкая",
        widthStandard: "Стандартная",
        widthWide: "Широкая",
        spacedColumns: "Промежутки между столбцами истории",
        networkLayout: "График сети",
        networkMirrored: "Зеркально",
        networkSplit: "Сверху и снизу",
        networkRising: "Оба вверх",
        caption: "Графики рисуются основным цветом темы. Системное время CPU, отдача и остальная занятая память — её вторым цветом."
    )

    static let es = MenuBarGraphThemeStrings(
        title: "Tema de las gráficas",
        lightMode: "Barra de menús clara",
        darkMode: "Barra de menús oscura",
        system: "Acento del sistema",
        mono: "Monocromo",
        blue: "Azul",
        green: "Verde",
        aqua: "Aguamarina",
        red: "Rojo",
        purple: "Morado",
        indigo: "Índigo",
        yellow: "Amarillo",
        pink: "Rosa",
        orange: "Naranja",
        graphite: "Grafito",
        softFormat: "%@ suave",
        lightBackground: "Fondo con la barra clara",
        backgroundFilled: "Oscuro",
        backgroundOutline: "Contorno",
        historyWidth: "Ancho del historial",
        widthNarrow: "Estrecho",
        widthStandard: "Estándar",
        widthWide: "Ancho",
        spacedColumns: "Separar las columnas del historial",
        networkLayout: "Gráfica de red",
        networkMirrored: "Espejo",
        networkSplit: "Arriba y abajo",
        networkRising: "Ambas hacia arriba",
        caption: "Las gráficas usan el color principal del tema. El tiempo de sistema de la CPU, la subida y el resto de la memoria usada usan su segundo color."
    )

    static let de = MenuBarGraphThemeStrings(
        title: "Diagrammfarben",
        lightMode: "Helle Menüleiste",
        darkMode: "Dunkle Menüleiste",
        system: "Systemakzent",
        mono: "Monochrom",
        blue: "Blau",
        green: "Grün",
        aqua: "Aqua",
        red: "Rot",
        purple: "Lila",
        indigo: "Indigo",
        yellow: "Gelb",
        pink: "Pink",
        orange: "Orange",
        graphite: "Graphit",
        softFormat: "%@ (gedämpft)",
        lightBackground: "Hintergrund bei heller Leiste",
        backgroundFilled: "Dunkel",
        backgroundOutline: "Umriss",
        historyWidth: "Verlaufsbreite",
        widthNarrow: "Schmal",
        widthStandard: "Standard",
        widthWide: "Breit",
        spacedColumns: "Verlaufsspalten mit Abstand",
        networkLayout: "Netzwerkdiagramm",
        networkMirrored: "Gespiegelt",
        networkSplit: "Oben und unten",
        networkRising: "Beide steigend",
        caption: "Diagramme nutzen die Hauptfarbe des Designs. CPU-Systemzeit, Upload und der übrige belegte Speicher nutzen die zweite Farbe."
    )

    static let fr = MenuBarGraphThemeStrings(
        title: "Thème des graphiques",
        lightMode: "Barre des menus claire",
        darkMode: "Barre des menus sombre",
        system: "Couleur d’accentuation",
        mono: "Monochrome",
        blue: "Bleu",
        green: "Vert",
        aqua: "Turquoise",
        red: "Rouge",
        purple: "Violet",
        indigo: "Indigo",
        yellow: "Jaune",
        pink: "Rose",
        orange: "Orange",
        graphite: "Graphite",
        softFormat: "%@ doux",
        lightBackground: "Fond avec la barre claire",
        backgroundFilled: "Sombre",
        backgroundOutline: "Contour",
        historyWidth: "Largeur de l’historique",
        widthNarrow: "Étroite",
        widthStandard: "Standard",
        widthWide: "Large",
        spacedColumns: "Espacer les colonnes de l’historique",
        networkLayout: "Graphique réseau",
        networkMirrored: "En miroir",
        networkSplit: "En haut et en bas",
        networkRising: "Les deux vers le haut",
        caption: "Les graphiques utilisent la couleur principale du thème. Le temps système du processeur, l’envoi et le reste de la mémoire utilisée prennent sa deuxième couleur."
    )

    static let it = MenuBarGraphThemeStrings(
        title: "Tema dei grafici",
        lightMode: "Barra dei menu chiara",
        darkMode: "Barra dei menu scura",
        system: "Colore di sistema",
        mono: "Monocromatico",
        blue: "Blu",
        green: "Verde",
        aqua: "Acqua",
        red: "Rosso",
        purple: "Viola",
        indigo: "Indaco",
        yellow: "Giallo",
        pink: "Rosa",
        orange: "Arancione",
        graphite: "Grafite",
        softFormat: "%@ tenue",
        lightBackground: "Sfondo con la barra chiara",
        backgroundFilled: "Scuro",
        backgroundOutline: "Contorno",
        historyWidth: "Larghezza della cronologia",
        widthNarrow: "Stretta",
        widthStandard: "Standard",
        widthWide: "Ampia",
        spacedColumns: "Distanzia le colonne della cronologia",
        networkLayout: "Grafico di rete",
        networkMirrored: "Speculare",
        networkSplit: "Sopra e sotto",
        networkRising: "Entrambi verso l’alto",
        caption: "I grafici usano il colore principale del tema. Il tempo di sistema della CPU, il caricamento e il resto della memoria usata usano il secondo colore."
    )

    static let ja = MenuBarGraphThemeStrings(
        title: "グラフのテーマ",
        lightMode: "明るいメニューバー",
        darkMode: "暗いメニューバー",
        system: "システムのアクセント",
        mono: "モノクロ",
        blue: "ブルー",
        green: "グリーン",
        aqua: "アクア",
        red: "レッド",
        purple: "パープル",
        indigo: "インディゴ",
        yellow: "イエロー",
        pink: "ピンク",
        orange: "オレンジ",
        graphite: "グラファイト",
        softFormat: "ソフト%@",
        lightBackground: "明るいバーでの背景",
        backgroundFilled: "ダーク",
        backgroundOutline: "枠線",
        historyWidth: "履歴の幅",
        widthNarrow: "狭い",
        widthStandard: "標準",
        widthWide: "広い",
        spacedColumns: "履歴の列に間隔を空ける",
        networkLayout: "ネットワークのグラフ",
        networkMirrored: "ミラー",
        networkSplit: "上と下",
        networkRising: "どちらも上向き",
        caption: "グラフはテーマのメインカラーで描かれます。CPUのシステム時間、アップロード、使用中メモリの残りは2番目の色を使います。"
    )

    static let ko = MenuBarGraphThemeStrings(
        title: "그래프 테마",
        lightMode: "밝은 메뉴 막대",
        darkMode: "어두운 메뉴 막대",
        system: "시스템 강조 색상",
        mono: "단색",
        blue: "파란색",
        green: "초록색",
        aqua: "아쿠아",
        red: "빨간색",
        purple: "보라색",
        indigo: "남색",
        yellow: "노란색",
        pink: "분홍색",
        orange: "주황색",
        graphite: "그래파이트",
        softFormat: "부드러운 %@",
        lightBackground: "밝은 막대에서의 배경",
        backgroundFilled: "어둡게",
        backgroundOutline: "윤곽선",
        historyWidth: "기록 너비",
        widthNarrow: "좁게",
        widthStandard: "표준",
        widthWide: "넓게",
        spacedColumns: "기록 열 사이에 간격 두기",
        networkLayout: "네트워크 그래프",
        networkMirrored: "대칭",
        networkSplit: "위와 아래",
        networkRising: "모두 위로",
        caption: "그래프는 테마의 기본 색상으로 그려집니다. CPU 시스템 시간, 업로드, 나머지 사용 중 메모리는 두 번째 색상을 사용합니다."
    )

    static let zhHans = MenuBarGraphThemeStrings(
        title: "图表主题",
        lightMode: "浅色菜单栏",
        darkMode: "深色菜单栏",
        system: "系统强调色",
        mono: "单色",
        blue: "蓝色",
        green: "绿色",
        aqua: "水绿色",
        red: "红色",
        purple: "紫色",
        indigo: "靛蓝",
        yellow: "黄色",
        pink: "粉色",
        orange: "橙色",
        graphite: "石墨色",
        softFormat: "柔和%@",
        lightBackground: "浅色菜单栏上的背景",
        backgroundFilled: "深色",
        backgroundOutline: "轮廓",
        historyWidth: "历史宽度",
        widthNarrow: "窄",
        widthStandard: "标准",
        widthWide: "宽",
        spacedColumns: "历史列之间留出间隔",
        networkLayout: "网络图表",
        networkMirrored: "镜像",
        networkSplit: "上下分开",
        networkRising: "都向上",
        caption: "图表使用主题的主色。CPU 系统时间、上传和其余已用内存使用第二种颜色。"
    )

    static let zhTW = MenuBarGraphThemeStrings(
        title: "圖表主題",
        lightMode: "淺色選單列",
        darkMode: "深色選單列",
        system: "系統強調色",
        mono: "單色",
        blue: "藍色",
        green: "綠色",
        aqua: "水綠色",
        red: "紅色",
        purple: "紫色",
        indigo: "靛藍",
        yellow: "黃色",
        pink: "粉紅色",
        orange: "橙色",
        graphite: "石墨色",
        softFormat: "柔和%@",
        lightBackground: "淺色選單列上的背景",
        backgroundFilled: "深色",
        backgroundOutline: "外框",
        historyWidth: "歷史寬度",
        widthNarrow: "窄",
        widthStandard: "標準",
        widthWide: "寬",
        spacedColumns: "歷史欄之間留出間隔",
        networkLayout: "網路圖表",
        networkMirrored: "鏡像",
        networkSplit: "上下分開",
        networkRising: "皆向上",
        caption: "圖表使用主題的主色。CPU 系統時間、上傳和其餘已用記憶體使用第二種顏色。"
    )

    static let zhHK = MenuBarGraphThemeStrings(
        title: "圖表主題",
        lightMode: "淺色選單列",
        darkMode: "深色選單列",
        system: "系統強調色",
        mono: "單色",
        blue: "藍色",
        green: "綠色",
        aqua: "水綠色",
        red: "紅色",
        purple: "紫色",
        indigo: "靛藍",
        yellow: "黃色",
        pink: "粉紅色",
        orange: "橙色",
        graphite: "石墨色",
        softFormat: "柔和%@",
        lightBackground: "淺色選單列上的背景",
        backgroundFilled: "深色",
        backgroundOutline: "外框",
        historyWidth: "歷史闊度",
        widthNarrow: "窄",
        widthStandard: "標準",
        widthWide: "闊",
        spacedColumns: "歷史欄之間留出間隔",
        networkLayout: "網絡圖表",
        networkMirrored: "鏡像",
        networkSplit: "上下分開",
        networkRising: "皆向上",
        caption: "圖表使用主題的主色。CPU 系統時間、上載和其餘已用記憶體使用第二種顏色。"
    )

    static let sk = MenuBarGraphThemeStrings(
        title: "Téma grafov",
        lightMode: "Svetlý panel s ponukami",
        darkMode: "Tmavý panel s ponukami",
        system: "Akcent systému",
        mono: "Jednofarebná",
        blue: "Modrá",
        green: "Zelená",
        aqua: "Akvamarínová",
        red: "Červená",
        purple: "Fialová",
        indigo: "Indigová",
        yellow: "Žltá",
        pink: "Ružová",
        orange: "Oranžová",
        graphite: "Grafitová",
        softFormat: "%@ (tlmená)",
        lightBackground: "Pozadie pri svetlom paneli",
        backgroundFilled: "Tmavé",
        backgroundOutline: "Obrys",
        historyWidth: "Šírka histórie",
        widthNarrow: "Úzka",
        widthStandard: "Štandardná",
        widthWide: "Široká",
        spacedColumns: "Medzery medzi stĺpcami histórie",
        networkLayout: "Graf siete",
        networkMirrored: "Zrkadlovo",
        networkSplit: "Hore a dole",
        networkRising: "Oba nahor",
        caption: "Grafy používajú hlavnú farbu témy. Systémový čas CPU, odosielanie a zvyšok použitej pamäte používajú jej druhú farbu."
    )

    static let uk = MenuBarGraphThemeStrings(
        title: "Тема графіків",
        lightMode: "Світлий рядок меню",
        darkMode: "Темний рядок меню",
        system: "Акцент системи",
        mono: "Монохром",
        blue: "Синій",
        green: "Зелений",
        aqua: "Бірюзовий",
        red: "Червоний",
        purple: "Фіолетовий",
        indigo: "Індиго",
        yellow: "Жовтий",
        pink: "Рожевий",
        orange: "Помаранчевий",
        graphite: "Графіт",
        softFormat: "%@ (приглушений)",
        lightBackground: "Тло у світлому рядку меню",
        backgroundFilled: "Темне",
        backgroundOutline: "Контур",
        historyWidth: "Ширина історії",
        widthNarrow: "Вузька",
        widthStandard: "Стандартна",
        widthWide: "Широка",
        spacedColumns: "Проміжки між стовпцями історії",
        networkLayout: "Графік мережі",
        networkMirrored: "Дзеркально",
        networkSplit: "Згори і знизу",
        networkRising: "Обидва вгору",
        caption: "Графіки малюються основним кольором теми. Системний час CPU, вивантаження та решта зайнятої пам’яті — її другим кольором."
    )
}
