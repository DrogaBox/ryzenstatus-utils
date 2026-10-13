// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Strings for the island's music visualizer. Same contract as the other
/// FeatureStrings structs: memberwise init with labeled arguments in
/// declaration order, one static per language, all in this file.
struct NotchMusicVisualizerStrings {
    let title: String
    let hint: String
    let modeTitle: String
    let modeTitleThenVisualizer: String
    let modeVisualizer: String
    let titleSeconds: String
    let secondsFormat: String
    let dances: String
    let dancesHint: String

    func name(of mode: NotchMusicVisualizerMode) -> String {
        switch mode {
        case .title: return modeTitle
        case .titleThenVisualizer: return modeTitleThenVisualizer
        case .visualizer: return modeVisualizer
        }
    }

    func seconds(_ value: Int) -> String { String(format: secondsFormat, value) }
}

extension FeatureStrings {
    static func notchMusicVisualizer(_ language: AppLanguage) -> NotchMusicVisualizerStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ru: return .ru
        case .tr: return .tr
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension NotchMusicVisualizerStrings {
    static let enUS = NotchMusicVisualizerStrings(
        title: "Middle of the island while music plays",
        hint: "On a capsule island, what sits between the cover and the bars. The visualizer follows the real sound when “Bars follow the music” is on, and keeps its own motion otherwise.",
        modeTitle: "Song name",
        modeTitleThenVisualizer: "Name, then visualizer",
        modeVisualizer: "Visualizer only",
        titleSeconds: "Show the name for",
        secondsFormat: "%d s",
        dances: "Companion dances to the music",
        dancesHint: "It nods to the bass at the end of the island while the visualizer plays."
    )

    static let ptBR = NotchMusicVisualizerStrings(
        title: "Centro da ilha com música",
        hint: "Numa ilha em cápsula, o que fica entre a capa e as barras. O visualizador segue o som real com “Barras seguem a música” ligado e, sem ele, tem movimento próprio.",
        modeTitle: "Nome da música",
        modeTitleThenVisualizer: "Nome, depois visualizador",
        modeVisualizer: "Só visualizador",
        titleSeconds: "Mostrar o nome por",
        secondsFormat: "%d s",
        dances: "O companheiro dança com a música",
        dancesHint: "Ele balança a cabeça com o grave na ponta da ilha enquanto o visualizador toca."
    )

    static let es = NotchMusicVisualizerStrings(
        title: "Centro de la isla con música",
        hint: "En la isla en cápsula, lo que va entre la portada y las barras. El visualizador sigue el sonido real con “Las barras siguen la música” activado y, si no, tiene su propio movimiento.",
        modeTitle: "Nombre de la canción",
        modeTitleThenVisualizer: "Nombre y luego visualizador",
        modeVisualizer: "Solo visualizador",
        titleSeconds: "Mostrar el nombre durante",
        secondsFormat: "%d s",
        dances: "El compañero baila con la música",
        dancesHint: "Mueve la cabeza con los graves en la punta de la isla mientras suena el visualizador."
    )

    static let sk = NotchMusicVisualizerStrings(
        title: "Stred ostrova počas hudby",
        hint: "Na ostrove v tvare kapsuly to, čo je medzi obalom a pruhmi. Vizualizér sleduje skutočný zvuk, keď je zapnuté „Pruhy sledujú hudbu“, inak sa hýbe sám.",
        modeTitle: "Názov skladby",
        modeTitleThenVisualizer: "Názov, potom vizualizér",
        modeVisualizer: "Len vizualizér",
        titleSeconds: "Zobraziť názov na",
        secondsFormat: "%d s",
        dances: "Spoločník tancuje do hudby",
        dancesHint: "Na konci ostrova kýva hlavou do basov, kým hrá vizualizér."
    )

    static let de = NotchMusicVisualizerStrings(
        title: "Mitte der Insel bei Musik",
        hint: "Bei einer Kapsel-Insel das, was zwischen Cover und Balken steht. Der Visualizer folgt dem echten Klang, wenn „Balken folgen der Musik“ an ist, sonst bewegt er sich von selbst.",
        modeTitle: "Songname",
        modeTitleThenVisualizer: "Name, dann Visualizer",
        modeVisualizer: "Nur Visualizer",
        titleSeconds: "Namen anzeigen für",
        secondsFormat: "%d s",
        dances: "Begleiter tanzt zur Musik",
        dancesHint: "Er nickt am Ende der Insel zum Bass, solange der Visualizer läuft."
    )

    static let fr = NotchMusicVisualizerStrings(
        title: "Centre de l’île avec la musique",
        hint: "Sur une île en capsule, ce qui se trouve entre la pochette et les barres. Le visualiseur suit le vrai son quand « Les barres suivent la musique » est activé, sinon il bouge tout seul.",
        modeTitle: "Nom du morceau",
        modeTitleThenVisualizer: "Nom, puis visualiseur",
        modeVisualizer: "Visualiseur seul",
        titleSeconds: "Afficher le nom pendant",
        secondsFormat: "%d s",
        dances: "Le compagnon danse sur la musique",
        dancesHint: "Il hoche la tête sur les basses au bout de l’île pendant le visualiseur."
    )

    static let it = NotchMusicVisualizerStrings(
        title: "Centro dell’isola con la musica",
        hint: "Su un’isola a capsula, ciò che sta tra la copertina e le barre. Il visualizzatore segue il suono reale con «Le barre seguono la musica» attivo, altrimenti si muove da solo.",
        modeTitle: "Nome del brano",
        modeTitleThenVisualizer: "Nome, poi visualizzatore",
        modeVisualizer: "Solo visualizzatore",
        titleSeconds: "Mostra il nome per",
        secondsFormat: "%d s",
        dances: "Il compagno balla con la musica",
        dancesHint: "Muove la testa sui bassi in fondo all’isola mentre suona il visualizzatore."
    )

    static let ru = NotchMusicVisualizerStrings(
        title: "Центр острова при музыке",
        hint: "На острове-капсуле то, что между обложкой и полосками. Визуализатор следует реальному звуку при включённом «Полоски следуют музыке», иначе двигается сам.",
        modeTitle: "Название песни",
        modeTitleThenVisualizer: "Название, затем визуализатор",
        modeVisualizer: "Только визуализатор",
        titleSeconds: "Показывать название",
        secondsFormat: "%d с",
        dances: "Компаньон танцует под музыку",
        dancesHint: "Он кивает в такт басам в конце острова, пока играет визуализатор."
    )

    static let tr = NotchMusicVisualizerStrings(
        title: "Müzik çalarken adanın ortası",
        hint: "Kapsül adada kapak ile çubuklar arasında ne görüneceği. Görselleştirici, “Çubuklar müziği izler” açıkken gerçek sesi izler, değilse kendi hareketini yapar.",
        modeTitle: "Şarkı adı",
        modeTitleThenVisualizer: "Ad, sonra görselleştirici",
        modeVisualizer: "Yalnızca görselleştirici",
        titleSeconds: "Adı gösterme süresi",
        secondsFormat: "%d sn",
        dances: "Arkadaş müzikle dans eder",
        dancesHint: "Görselleştirici çalarken adanın ucunda baslara göre başını sallar."
    )

    static let ja = NotchMusicVisualizerStrings(
        title: "音楽再生中のアイランド中央",
        hint: "カプセル型アイランドで、ジャケットとバーの間に表示するもの。「バーが音楽に合わせて動く」がオンなら実際の音に合わせて動き、オフなら独自の動きをします。",
        modeTitle: "曲名",
        modeTitleThenVisualizer: "曲名のあとビジュアライザ",
        modeVisualizer: "ビジュアライザのみ",
        titleSeconds: "曲名の表示時間",
        secondsFormat: "%d秒",
        dances: "コンパニオンが音楽に合わせて踊る",
        dancesHint: "ビジュアライザの再生中、アイランドの端で低音に合わせてうなずきます。"
    )

    static let ko = NotchMusicVisualizerStrings(
        title: "음악 재생 중 아일랜드 가운데",
        hint: "캡슐형 아일랜드에서 앨범 커버와 막대 사이에 표시할 내용입니다. ‘막대가 음악을 따라 움직임’이 켜져 있으면 실제 소리를 따르고, 아니면 자체적으로 움직입니다.",
        modeTitle: "노래 제목",
        modeTitleThenVisualizer: "제목 후 비주얼라이저",
        modeVisualizer: "비주얼라이저만",
        titleSeconds: "제목 표시 시간",
        secondsFormat: "%d초",
        dances: "컴패니언이 음악에 맞춰 춤추기",
        dancesHint: "비주얼라이저가 재생되는 동안 아일랜드 끝에서 베이스에 맞춰 고개를 끄덕입니다."
    )

    static let zhHans = NotchMusicVisualizerStrings(
        title: "播放音乐时灵动岛中间",
        hint: "胶囊灵动岛在封面和条形之间显示的内容。开启“音柱跟随音乐”时可视化效果跟随真实声音，否则按自身节奏律动。",
        modeTitle: "歌曲名称",
        modeTitleThenVisualizer: "先显示名称，再显示可视化",
        modeVisualizer: "仅可视化",
        titleSeconds: "名称显示时长",
        secondsFormat: "%d 秒",
        dances: "伙伴随音乐跳舞",
        dancesHint: "可视化播放时，它会在灵动岛末端随低音点头。"
    )

    static let zhTW = NotchMusicVisualizerStrings(
        title: "播放音樂時動態島中間",
        hint: "膠囊動態島在封面與長條之間顯示的內容。開啟「音柱跟隨音樂」時視覺化效果跟隨真實聲音，否則依自身節奏律動。",
        modeTitle: "歌曲名稱",
        modeTitleThenVisualizer: "先顯示名稱，再顯示視覺化",
        modeVisualizer: "僅視覺化",
        titleSeconds: "名稱顯示時間",
        secondsFormat: "%d 秒",
        dances: "夥伴隨音樂跳舞",
        dancesHint: "視覺化播放時，它會在動態島末端隨低音點頭。"
    )

    static let zhHK = NotchMusicVisualizerStrings(
        title: "播放音樂時動態島中間",
        hint: "膠囊動態島喺封面同長條之間顯示嘅內容。開啟「音柱跟隨音樂」時視覺化效果跟隨真實聲音，否則按自己節奏律動。",
        modeTitle: "歌曲名稱",
        modeTitleThenVisualizer: "先顯示名稱，再顯示視覺化",
        modeVisualizer: "只顯示視覺化",
        titleSeconds: "名稱顯示時間",
        secondsFormat: "%d 秒",
        dances: "夥伴隨音樂跳舞",
        dancesHint: "視覺化播放時，佢會喺動態島末端隨低音點頭。"
    )

    static let uk = NotchMusicVisualizerStrings(
        title: "Центр острова під час музики",
        hint: "На острові-капсулі те, що між обкладинкою та смужками. Візуалізатор стежить за справжнім звуком, коли увімкнено «Смужки слідують за музикою», інакше рухається сам.",
        modeTitle: "Назва пісні",
        modeTitleThenVisualizer: "Назва, потім візуалізатор",
        modeVisualizer: "Лише візуалізатор",
        titleSeconds: "Показувати назву",
        secondsFormat: "%d с",
        dances: "Компаньйон танцює під музику",
        dancesHint: "Він киває в такт басам у кінці острова, поки грає візуалізатор."
    )
}
