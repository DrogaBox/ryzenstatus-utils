// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

struct MenuBarAppearanceStrings {
    let label: String
    let values: String
    let bars: String
    let pie: String
    let sparkline: String
    let histogram: String
    let individualPerMetric: String
    let popoverStyle: String
    let classicCards: String
    let iStatsWidgets: String
    let caption: String
    let customize: String
    let normalColor: String
    let mediumColor: String
    let highColor: String
    let mediumFrom: String
    let highFrom: String
}

extension FeatureStrings {
    static func menuBarAppearance(_ language: AppLanguage) -> MenuBarAppearanceStrings {
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

extension MenuBarAppearanceStrings {
    static let enUS = MenuBarAppearanceStrings(
        label: "Usage display",
        values: "Values",
        bars: "Bars",
        pie: "Donut Rings",
        sparkline: "Line Graph",
        histogram: "Histogram",
        individualPerMetric: "Individual Per-Metric Style",
        popoverStyle: "Popover Style",
        classicCards: "Classic Cards",
        iStatsWidgets: "iStats Widgets",
        caption: "Graph styles apply to CPU, GPU, memory and disk usage. Other readings stay numeric.",
        customize: "Bar colors and limits",
        normalColor: "Normal color",
        mediumColor: "Medium color",
        highColor: "High color",
        mediumFrom: "Medium from",
        highFrom: "High from"
    )

    static let ptBR = MenuBarAppearanceStrings(
        label: "Exibição de uso",
        values: "Valores",
        bars: "Barras",
        pie: "Anéis Circular",
        sparkline: "Gráfico de Linha",
        histogram: "Histograma",
        individualPerMetric: "Estilo Individual por Métrica",
        popoverStyle: "Estilo do Painel",
        classicCards: "Cartões Clássicos",
        iStatsWidgets: "Widgets iStats",
        caption: "As barras e gráficos mostram o uso de CPU, GPU, memória e disco. As outras leituras continuam numéricas.",
        customize: "Cores e limites das barras",
        normalColor: "Cor normal",
        mediumColor: "Cor média",
        highColor: "Cor alta",
        mediumFrom: "Médio a partir de",
        highFrom: "Alto a partir de"
    )

    static let tr = MenuBarAppearanceStrings(
        label: "Kullanım görünümü",
        values: "Değerler",
        bars: "Çubuklar",
        pie: "Halka Çember",
        sparkline: "Çizgi Grafiği",
        histogram: "Histogram",
        individualPerMetric: "Metrik Başına Özel Stil",
        popoverStyle: "Açılır Panel Stili",
        classicCards: "Klasik Kartlar",
        iStatsWidgets: "iStats Araçları",
        caption: "Çubuklar CPU, GPU, bellek ve disk kullanımını gösterir. Diğer ölçümler sayısal kalır.",
        customize: "Çubuk renkleri ve sınırları",
        normalColor: "Normal renk",
        mediumColor: "Orta renk",
        highColor: "Yüksek renk",
        mediumFrom: "Orta başlangıcı",
        highFrom: "Yüksek başlangıcı"
    )

    static let ru = MenuBarAppearanceStrings(
        label: "Отображение нагрузки",
        values: "Значения",
        bars: "Шкалы",
        pie: "Кольцевой",
        sparkline: "Линейный график",
        histogram: "Гистограмма",
        individualPerMetric: "Индивидуальный стиль метрик",
        popoverStyle: "Стиль панели",
        classicCards: "Классические карточки",
        iStatsWidgets: "Виджеты iStats",
        caption: "Шкалы показывают загрузку CPU, GPU, памяти и диска. Остальные показатели остаются числовыми.",
        customize: "Цвета и пороги шкал",
        normalColor: "Обычный цвет",
        mediumColor: "Средний цвет",
        highColor: "Высокий цвет",
        mediumFrom: "Средний от",
        highFrom: "Высокий от"
    )

    static let es = MenuBarAppearanceStrings(
        label: "Vista de uso",
        values: "Valores",
        bars: "Barras",
        pie: "Anillo Circular",
        sparkline: "Gráfico de Línea",
        histogram: "Histograma",
        individualPerMetric: "Estilo Individual por Métrica",
        popoverStyle: "Estilo de Panel",
        classicCards: "Tarjetas Clásicas",
        iStatsWidgets: "Widgets iStats",
        caption: "Los gráficos muestran el uso de CPU, GPU, memoria y disco. Las demás lecturas siguen siendo numéricas.",
        customize: "Colores y límites de las barras",
        normalColor: "Color normal",
        mediumColor: "Color medio",
        highColor: "Color alto",
        mediumFrom: "Medio desde",
        highFrom: "Alto desde"
    )

    static let de = MenuBarAppearanceStrings(
        label: "Auslastungsanzeige",
        values: "Werte",
        bars: "Balken",
        pie: "Ringdiagramm",
        sparkline: "Liniendiagramm",
        histogram: "Histogramm",
        individualPerMetric: "Individueller Metrik-Stil",
        popoverStyle: "Popover-Stil",
        classicCards: "Klassische Karten",
        iStatsWidgets: "iStats-Widgets",
        caption: "Balken zeigen die Auslastung von CPU, GPU, Speicher und Festplatte. Andere Messwerte bleiben numerisch.",
        customize: "Balkenfarben und Grenzwerte",
        normalColor: "Normale Farbe",
        mediumColor: "Mittlere Farbe",
        highColor: "Hohe Farbe",
        mediumFrom: "Mittel ab",
        highFrom: "Hoch ab"
    )

    static let fr = MenuBarAppearanceStrings(
        label: "Affichage de l’utilisation",
        values: "Valeurs",
        bars: "Barres",
        pie: "Anneau",
        sparkline: "Graphique linéaire",
        histogram: "Histogramme",
        individualPerMetric: "Style individuel par métrique",
        popoverStyle: "Style du panneau",
        classicCards: "Cartes classiques",
        iStatsWidgets: "Widgets iStats",
        caption: "Les barres indiquent l’utilisation du CPU, du GPU, de la mémoire et du disque. Les autres mesures restent numériques.",
        customize: "Couleurs et seuils des barres",
        normalColor: "Couleur normale",
        mediumColor: "Couleur moyenne",
        highColor: "Couleur élevée",
        mediumFrom: "Moyen à partir de",
        highFrom: "Élevé à partir de"
    )

    static let it = MenuBarAppearanceStrings(
        label: "Visualizzazione utilizzo",
        values: "Valori",
        bars: "Barre",
        pie: "Anello",
        sparkline: "Grafico a linee",
        histogram: "Istogramma",
        individualPerMetric: "Stile individuale per metrica",
        popoverStyle: "Stile pannello",
        classicCards: "Schede classiche",
        iStatsWidgets: "Widget iStats",
        caption: "Le barre mostrano l’utilizzo di CPU, GPU, memoria e disco. Le altre letture restano numeriche.",
        customize: "Colori e soglie delle barre",
        normalColor: "Colore normale",
        mediumColor: "Colore medio",
        highColor: "Colore alto",
        mediumFrom: "Medio da",
        highFrom: "Alto da"
    )

    static let ja = MenuBarAppearanceStrings(
        label: "使用率の表示",
        values: "数値",
        bars: "バー",
        pie: "ドーナツ型",
        sparkline: "折れ線グラフ",
        histogram: "ヒストグラム",
        individualPerMetric: "メトリクスごとの個別スタイル",
        popoverStyle: "ポップオーバースタイル",
        classicCards: "クラシックカード",
        iStatsWidgets: "iStats ウィジェット",
        caption: "CPU、GPU、メモリ、ディスクの使用率をバーで表示します。その他の測定値は数値のままです。",
        customize: "バーの色としきい値",
        normalColor: "通常の色",
        mediumColor: "中程度の色",
        highColor: "高負荷の色",
        mediumFrom: "中程度の開始",
        highFrom: "高負荷の開始"
    )

    static let ko = MenuBarAppearanceStrings(
        label: "사용량 표시",
        values: "값",
        bars: "막대",
        pie: "도넛 링",
        sparkline: "선 그래프",
        histogram: "히스토그램",
        individualPerMetric: "항목별 개별 스타일",
        popoverStyle: "팝오버 스타일",
        classicCards: "클래식 카드",
        iStatsWidgets: "iStats 위젯",
        caption: "CPU, GPU, 메모리 및 디스크 사용량을 막대로 표시합니다. 다른 측정값은 숫자로 유지됩니다.",
        customize: "막대 색상 및 기준",
        normalColor: "보통 색상",
        mediumColor: "중간 색상",
        highColor: "높음 색상",
        mediumFrom: "중간 시작",
        highFrom: "높음 시작"
    )

    static let zhHans = MenuBarAppearanceStrings(
        label: "使用率显示",
        values: "数值",
        bars: "条形",
        pie: "环形图",
        sparkline: "折线图",
        histogram: "直方图",
        individualPerMetric: "各项单独样式",
        popoverStyle: "弹出面板样式",
        classicCards: "经典卡片",
        iStatsWidgets: "iStats 小组件",
        caption: "CPU、GPU、内存和磁盘使用率以条形显示。其他读数保持数字显示。",
        customize: "条形颜色和阈值",
        normalColor: "正常颜色",
        mediumColor: "中等颜色",
        highColor: "高负载颜色",
        mediumFrom: "中等起点",
        highFrom: "高负载起点"
    )

    static let zhTW = MenuBarAppearanceStrings(
        label: "使用率顯示",
        values: "數值",
        bars: "長條",
        pie: "環形圖",
        sparkline: "折線圖",
        histogram: "長條圖",
        individualPerMetric: "各項個別樣式",
        popoverStyle: "彈出面板樣式",
        classicCards: "經典卡片",
        iStatsWidgets: "iStats 小工具",
        caption: "CPU、GPU、記憶體和磁碟使用率以長條顯示。其他讀數維持數字顯示。",
        customize: "長條顏色和門檻",
        normalColor: "正常顏色",
        mediumColor: "中等顏色",
        highColor: "高負載顏色",
        mediumFrom: "中等起點",
        highFrom: "高負載起點"
    )

    static let zhHK = MenuBarAppearanceStrings(
        label: "使用率顯示",
        values: "數值",
        bars: "長條",
        pie: "環形圖",
        sparkline: "折線圖",
        histogram: "長條圖",
        individualPerMetric: "各項個別樣式",
        popoverStyle: "彈出面板樣式",
        classicCards: "經典卡片",
        iStatsWidgets: "iStats 小工具",
        caption: "CPU、GPU、記憶體及磁碟使用率以長條顯示。其他讀數維持數字顯示。",
        customize: "長條顏色及門檻",
        normalColor: "正常顏色",
        mediumColor: "中等顏色",
        highColor: "高負載顏色",
        mediumFrom: "中等起點",
        highFrom: "高負載起點"
    )
}
