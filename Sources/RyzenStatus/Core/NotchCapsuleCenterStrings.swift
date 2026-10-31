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
    let metricLabel: String
    let cpuTemperature: String
    let cpuUsage: String
    let gpuTemperature: String
    let memory: String
    let network: String
    let carousel: String
    let cpuPower: String
    let peakFrequency: String
    /// The reading comes from the graphics card's fan, so it says so.
    let fanSpeed: String
    /// The readings a capsule shows: peak and average clock as `%.2f` GHz,
    /// the GPU fan as `%.0f` RPM.
    let boostReading: String
    let clockReading: String
    let fanReading: String

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
        network: "Network download",
        carousel: "Trend carousel",
        cpuPower: "CPU power (PPT)",
        peakFrequency: "Peak clock / boost",
        fanSpeed: "GPU fan speed",
        boostReading: "Boost %.2f GHz",
        clockReading: "Clock %.2f GHz",
        fanReading: "GPU fan %.0f RPM")
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
        network: "Download da rede",
        carousel: "Carrossel de tendências",
        cpuPower: "Potência da CPU (PPT)",
        peakFrequency: "Clock de pico / boost",
        fanSpeed: "Velocidade da ventoinha da GPU",
        boostReading: "Boost %.2f GHz",
        clockReading: "Clock %.2f GHz",
        fanReading: "Ventoinha GPU %.0f RPM")
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
        network: "Ağ indirme",
        carousel: "Eğilim karuseli",
        cpuPower: "CPU gücü (PPT)",
        peakFrequency: "Tepe saat / boost",
        fanSpeed: "GPU fan hızı",
        boostReading: "Boost %.2f GHz",
        clockReading: "Saat %.2f GHz",
        fanReading: "GPU fanı %.0f RPM")
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
        network: "Загрузка из сети",
        carousel: "Карусель трендов",
        cpuPower: "Мощность ЦП (PPT)",
        peakFrequency: "Пиковая частота / буст",
        fanSpeed: "Скорость вентилятора ГП",
        boostReading: "Буст %.2f ГГц",
        clockReading: "Частота %.2f ГГц",
        fanReading: "Вент. ГП %.0f об/мин")
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
        network: "Descarga de red",
        carousel: "Carrusel de tendencias",
        cpuPower: "Potencia de la CPU (PPT)",
        peakFrequency: "Frecuencia máxima / boost",
        fanSpeed: "Velocidad del ventilador de la GPU",
        boostReading: "Boost %.2f GHz",
        clockReading: "Reloj %.2f GHz",
        fanReading: "Ventilador GPU %.0f RPM")
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
        network: "Sťahovanie zo siete",
        carousel: "Karusel trendov",
        cpuPower: "Výkon CPU (PPT)",
        peakFrequency: "Špičková frekvencia / boost",
        fanSpeed: "Otáčky ventilátora GPU",
        boostReading: "Boost %.2f GHz",
        clockReading: "Frekvencia %.2f GHz",
        fanReading: "Ventilátor GPU %.0f ot./min")
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
        network: "Netzwerk-Download",
        carousel: "Trend-Karussell",
        cpuPower: "CPU-Leistung (PPT)",
        peakFrequency: "Spitzentakt / Boost",
        fanSpeed: "GPU-Lüfterdrehzahl",
        boostReading: "Boost %.2f GHz",
        clockReading: "Takt %.2f GHz",
        fanReading: "GPU-Lüfter %.0f U/min")
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
        network: "Téléchargement réseau",
        carousel: "Carrousel de tendances",
        cpuPower: "Puissance CPU (PPT)",
        peakFrequency: "Fréquence de pointe / boost",
        fanSpeed: "Vitesse du ventilateur GPU",
        boostReading: "Boost %.2f GHz",
        clockReading: "Fréquence %.2f GHz",
        fanReading: "Ventilateur GPU %.0f tr/min")
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
        network: "Download di rete",
        carousel: "Carosello tendenze",
        cpuPower: "Potenza CPU (PPT)",
        peakFrequency: "Clock di picco / boost",
        fanSpeed: "Velocità ventola GPU",
        boostReading: "Boost %.2f GHz",
        clockReading: "Clock %.2f GHz",
        fanReading: "Ventola GPU %.0f RPM")
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
        network: "ネットワーク受信",
        carousel: "トレンドカルーセル",
        cpuPower: "CPU電力（PPT）",
        peakFrequency: "ピーククロック／ブースト",
        fanSpeed: "GPUファン回転数",
        boostReading: "ブースト %.2f GHz",
        clockReading: "クロック %.2f GHz",
        fanReading: "GPUファン %.0f RPM")
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
        network: "네트워크 다운로드",
        carousel: "추세 캐러셀",
        cpuPower: "CPU 전력(PPT)",
        peakFrequency: "최대 클럭 / 부스트",
        fanSpeed: "GPU 팬 속도",
        boostReading: "부스트 %.2f GHz",
        clockReading: "클럭 %.2f GHz",
        fanReading: "GPU 팬 %.0f RPM")
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
        network: "网络下载",
        carousel: "趋势轮播",
        cpuPower: "CPU 功耗（PPT）",
        peakFrequency: "峰值频率／加速",
        fanSpeed: "GPU 风扇转速",
        boostReading: "加速 %.2f GHz",
        clockReading: "频率 %.2f GHz",
        fanReading: "GPU 风扇 %.0f RPM")
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
        network: "網路下載",
        carousel: "趨勢輪播",
        cpuPower: "CPU 功耗（PPT）",
        peakFrequency: "峰值時脈／加速",
        fanSpeed: "GPU 風扇轉速",
        boostReading: "加速 %.2f GHz",
        clockReading: "時脈 %.2f GHz",
        fanReading: "GPU 風扇 %.0f RPM")
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
        network: "網絡下載",
        carousel: "趨勢輪播",
        cpuPower: "CPU 功耗（PPT）",
        peakFrequency: "峰值時脈／加速",
        fanSpeed: "GPU 風扇轉速",
        boostReading: "加速 %.2f GHz",
        clockReading: "時脈 %.2f GHz",
        fanReading: "GPU 風扇 %.0f RPM")
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
        network: "Завантаження з мережі",
        carousel: "Карусель трендів",
        cpuPower: "Потужність ЦП (PPT)",
        peakFrequency: "Пікова частота / буст",
        fanSpeed: "Швидкість вентилятора ГП",
        boostReading: "Буст %.2f ГГц",
        clockReading: "Частота %.2f ГГц",
        fanReading: "Вент. ГП %.0f об/хв")
}
