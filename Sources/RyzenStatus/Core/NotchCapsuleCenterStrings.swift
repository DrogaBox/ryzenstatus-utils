// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The capsule centre preference: what a capsule shows between a song's cover and bars.
struct NotchCapsuleCenterStrings {
    let title: String
    let caption: String
    let none: String
    let song: String
    let metric: String
    let rotate: String
    let clock: String
    var carousel: String = "Trend carousel"
    let metricLabel: String
    let cpuTemperature: String
    let cpuUsage: String
    let gpuTemperature: String
    let memory: String
    let network: String
    var cpuPower: String = "CPU power (PPT)"
    var peakFrequency: String = "Peak clock / boost"
    var fanSpeed: String = "Fan speed"

    func title(for center: NotchCapsuleCenter) -> String {
        switch center {
        case .none: return none
        case .song: return song
        case .metric: return metric
        case .rotate: return rotate
        case .clock: return clock
        case .carousel: return carousel
        }
    }

    func title(for metric: NotchCapsuleMetric) -> String {
        switch metric {
        case .cpuTemperature: return cpuTemperature
        case .cpuUsage: return cpuUsage
        case .gpuTemperature: return gpuTemperature
        case .memory: return memory
        case .network: return network
        case .cpuPower: return cpuPower
        case .peakFrequency: return peakFrequency
        case .fanSpeed: return fanSpeed
        }
    }
}

extension FeatureStrings {
    static func notchCapsuleCenter(_ language: AppLanguage) -> NotchCapsuleCenterStrings {
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

extension NotchCapsuleCenterStrings {
    static let enUS = NotchCapsuleCenterStrings(
        title: "Capsule center",
        caption: "Without a camera, the middle of the capsule can show something while a song plays, and at rest beside the companion. With Nothing, the capsule shrinks to the cover and the bars.",
        none: "Nothing",
        song: "Song",
        metric: "Metric",
        rotate: "Song and metric",
        clock: "Clock",
        metricLabel: "Metric",
        cpuTemperature: "CPU temperature",
        cpuUsage: "CPU usage",
        gpuTemperature: "GPU temperature",
        memory: "Memory",
        network: "Network download")
    static let ptBR = NotchCapsuleCenterStrings(
        title: "Centro da cápsula",
        caption: "Sem câmera, o meio da cápsula pode mostrar algo enquanto toca uma música e, em repouso, ao lado do companheiro. Com Nada, a cápsula encolhe até a capa e as barras.",
        none: "Nada",
        song: "Música",
        metric: "Métrica",
        rotate: "Música e métrica",
        clock: "Relógio",
        metricLabel: "Métrica",
        cpuTemperature: "Temperatura da CPU",
        cpuUsage: "Uso da CPU",
        gpuTemperature: "Temperatura da GPU",
        memory: "Memória",
        network: "Download da rede")
    static let tr = NotchCapsuleCenterStrings(
        title: "Kapsül ortası",
        caption: "Kamera olmadığında, şarkı çalarken ve beklemedeyken arkadaşın yanında kapsülün ortası bir şey gösterebilir. Hiçbiri seçiliyse kapsül kapak ve çubuklara kadar küçülür.",
        none: "Hiçbiri",
        song: "Şarkı",
        metric: "Ölçüm",
        rotate: "Şarkı ve ölçüm",
        clock: "Saat",
        metricLabel: "Ölçüm",
        cpuTemperature: "CPU sıcaklığı",
        cpuUsage: "CPU kullanımı",
        gpuTemperature: "GPU sıcaklığı",
        memory: "Bellek",
        network: "Ağ indirme")
    static let ru = NotchCapsuleCenterStrings(
        title: "Центр капсулы",
        caption: "Без камеры середина капсулы может что-то показывать, пока играет музыка, а в покое — рядом с компаньоном. С вариантом «Ничего» капсула сжимается до обложки и полос.",
        none: "Ничего",
        song: "Песня",
        metric: "Показатель",
        rotate: "Песня и показатель",
        clock: "Часы",
        metricLabel: "Показатель",
        cpuTemperature: "Температура ЦП",
        cpuUsage: "Загрузка ЦП",
        gpuTemperature: "Температура ГП",
        memory: "Память",
        network: "Загрузка из сети")
    static let es = NotchCapsuleCenterStrings(
        title: "Centro de la cápsula",
        caption: "Sin cámara, el centro de la cápsula puede mostrar algo mientras suena una canción y, en reposo, junto al compañero. Con Nada, la cápsula se encoge hasta la carátula y las barras.",
        none: "Nada",
        song: "Canción",
        metric: "Métrica",
        rotate: "Canción y métrica",
        clock: "Reloj",
        metricLabel: "Métrica",
        cpuTemperature: "Temperatura de la CPU",
        cpuUsage: "Uso de la CPU",
        gpuTemperature: "Temperatura de la GPU",
        memory: "Memoria",
        network: "Descarga de red")
    static let sk = NotchCapsuleCenterStrings(
        title: "Stred kapsuly",
        caption: "Bez kamery môže stred kapsuly niečo zobrazovať, kým hrá skladba, a v pokoji vedľa spoločníka. Pri možnosti Nič sa kapsula zmenší na obal a pruhy.",
        none: "Nič",
        song: "Skladba",
        metric: "Metrika",
        rotate: "Skladba a metrika",
        clock: "Hodiny",
        metricLabel: "Metrika",
        cpuTemperature: "Teplota CPU",
        cpuUsage: "Využitie CPU",
        gpuTemperature: "Teplota GPU",
        memory: "Pamäť",
        network: "Sťahovanie zo siete")
    static let de = NotchCapsuleCenterStrings(
        title: "Kapselmitte",
        caption: "Ohne Kamera kann die Mitte der Kapsel etwas anzeigen, während ein Titel läuft, und in Ruhe neben dem Begleiter. Mit „Nichts“ schrumpft die Kapsel auf Cover und Balken.",
        none: "Nichts",
        song: "Titel",
        metric: "Messwert",
        rotate: "Titel und Messwert",
        clock: "Uhr",
        metricLabel: "Messwert",
        cpuTemperature: "CPU-Temperatur",
        cpuUsage: "CPU-Auslastung",
        gpuTemperature: "GPU-Temperatur",
        memory: "Arbeitsspeicher",
        network: "Netzwerk-Download")
    static let fr = NotchCapsuleCenterStrings(
        title: "Centre de la capsule",
        caption: "Sans caméra, le centre de la capsule peut afficher quelque chose pendant la lecture d’un morceau et, au repos, à côté du compagnon. Avec Rien, la capsule se réduit à la pochette et aux barres.",
        none: "Rien",
        song: "Morceau",
        metric: "Mesure",
        rotate: "Morceau et mesure",
        clock: "Horloge",
        metricLabel: "Mesure",
        cpuTemperature: "Température du CPU",
        cpuUsage: "Utilisation du CPU",
        gpuTemperature: "Température du GPU",
        memory: "Mémoire",
        network: "Téléchargement réseau")
    static let it = NotchCapsuleCenterStrings(
        title: "Centro della capsula",
        caption: "Senza fotocamera, il centro della capsula può mostrare qualcosa mentre suona un brano e, a riposo, accanto al compagno. Con Niente, la capsula si riduce a copertina e barre.",
        none: "Niente",
        song: "Brano",
        metric: "Metrica",
        rotate: "Brano e metrica",
        clock: "Orologio",
        metricLabel: "Metrica",
        cpuTemperature: "Temperatura CPU",
        cpuUsage: "Uso CPU",
        gpuTemperature: "Temperatura GPU",
        memory: "Memoria",
        network: "Download di rete")
    static let ja = NotchCapsuleCenterStrings(
        title: "カプセルの中央",
        caption: "カメラがない場合、曲の再生中や待機中（コンパニオンの横）にカプセルの中央に情報を表示できます。「なし」を選ぶと、カプセルはジャケットとバーだけの幅に縮みます。",
        none: "なし",
        song: "曲",
        metric: "指標",
        rotate: "曲と指標",
        clock: "時計",
        metricLabel: "指標",
        cpuTemperature: "CPU温度",
        cpuUsage: "CPU使用率",
        gpuTemperature: "GPU温度",
        memory: "メモリ",
        network: "ネットワーク受信")
    static let ko = NotchCapsuleCenterStrings(
        title: "캡슐 가운데",
        caption: "카메라가 없으면 노래가 재생되는 동안과 대기 중 동반자 옆에 캡슐 가운데에 정보를 표시할 수 있습니다. 없음을 선택하면 캡슐이 앨범 커버와 막대 크기로 줄어듭니다.",
        none: "없음",
        song: "노래",
        metric: "지표",
        rotate: "노래와 지표",
        clock: "시계",
        metricLabel: "지표",
        cpuTemperature: "CPU 온도",
        cpuUsage: "CPU 사용률",
        gpuTemperature: "GPU 온도",
        memory: "메모리",
        network: "네트워크 다운로드")
    static let zhHans = NotchCapsuleCenterStrings(
        title: "胶囊中部",
        caption: "没有摄像头时，播放歌曲期间以及待机时（在伙伴旁边）胶囊中部可以显示信息。选择“无”时，胶囊会缩小到只容纳封面和音量条。",
        none: "无",
        song: "歌曲",
        metric: "指标",
        rotate: "歌曲和指标",
        clock: "时钟",
        metricLabel: "指标",
        cpuTemperature: "CPU 温度",
        cpuUsage: "CPU 使用率",
        gpuTemperature: "GPU 温度",
        memory: "内存",
        network: "网络下载")
    static let zhTW = NotchCapsuleCenterStrings(
        title: "膠囊中央",
        caption: "沒有相機時，播放歌曲期間以及待機時（在夥伴旁邊）膠囊中央可以顯示資訊。選擇「無」時，膠囊會縮小到只容納封面和音量條。",
        none: "無",
        song: "歌曲",
        metric: "指標",
        rotate: "歌曲和指標",
        clock: "時鐘",
        metricLabel: "指標",
        cpuTemperature: "CPU 溫度",
        cpuUsage: "CPU 使用率",
        gpuTemperature: "GPU 溫度",
        memory: "記憶體",
        network: "網路下載")
    static let zhHK = NotchCapsuleCenterStrings(
        title: "膠囊中央",
        caption: "沒有相機時，播放歌曲期間以及待機時（在夥伴旁邊）膠囊中央可以顯示資訊。選擇「無」時，膠囊會縮小至只容納封面和音量條。",
        none: "無",
        song: "歌曲",
        metric: "指標",
        rotate: "歌曲和指標",
        clock: "時鐘",
        metricLabel: "指標",
        cpuTemperature: "CPU 溫度",
        cpuUsage: "CPU 使用率",
        gpuTemperature: "GPU 溫度",
        memory: "記憶體",
        network: "網絡下載")
    static let uk = NotchCapsuleCenterStrings(
        title: "Центр капсули",
        caption: "Без камери середина капсули може щось показувати, поки грає пісня, а в спокої — поруч із компаньйоном. З варіантом «Нічого» капсула стискається до обкладинки та смуг.",
        none: "Нічого",
        song: "Пісня",
        metric: "Показник",
        rotate: "Пісня і показник",
        clock: "Годинник",
        metricLabel: "Показник",
        cpuTemperature: "Температура ЦП",
        cpuUsage: "Завантаження ЦП",
        gpuTemperature: "Температура ГП",
        memory: "Пам’ять",
        network: "Завантаження з мережі")
}
