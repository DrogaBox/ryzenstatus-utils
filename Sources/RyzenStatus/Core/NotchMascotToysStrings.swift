// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The toys and charms of luck: their names and a line on what each does,
/// in the order of `NotchMascotAccessory.toyItems`.
struct NotchMascotToysStrings {
    let items: [String]
    let gags: [String]

    static let itemCount = 12

    func name(of accessory: NotchMascotAccessory) -> String? {
        NotchMascotAccessory.toyItems.firstIndex(of: accessory).map { items[$0] }
    }

    func gag(of accessory: NotchMascotAccessory) -> String? {
        NotchMascotAccessory.toyItems.firstIndex(of: accessory).map { gags[$0] }
    }

    var isComplete: Bool {
        items.count == Self.itemCount && gags.count == Self.itemCount
            && items.allSatisfy { !$0.isEmpty } && gags.allSatisfy { !$0.isEmpty }
    }
}

extension FeatureStrings {
    // swiftlint:disable:next function_body_length
    static func notchMascotToys(_ language: AppLanguage) -> NotchMascotToysStrings {
        switch language {
        case .enUS:
            return .init(items: ["Propeller Cap", "Shoulder Parrot", "Spring Shoes", "Skateboard", "Umbrella", "Yo-yo",
                                 "Bubble Wand", "Magnet", "Lucky Dice", "Fortune Cookie", "Snow Globe", "Instant Camera"],
                         gags: ["Spins up and lifts off a moment.", "Squawks and repeats what it hears.",
                                "Every step a bounce.", "Ollies and kickflips.", "Its own little rain, kept off.",
                                "Down and back up, again and again.", "A trail of floating bubbles.",
                                "Pulls coins out of nowhere.", "Rolls: anything can happen.", "Cracks open a fortune.",
                                "Shake it: it snows.", "Flash! A snapshot."])
        case .es:
            return .init(items: ["Gorra con hélice", "Loro de hombro", "Zapatos de muelle", "Monopatín", "Paraguas", "Yoyó",
                                 "Pompero", "Imán", "Dados de la suerte", "Galleta de la fortuna", "Bola de nieve",
                                 "Cámara instantánea"],
                         gags: ["Gira y despega un momento.", "Grazna y repite lo que oye.", "Cada paso, un bote.",
                                "Ollies y kickflips.", "Su propia lluvia, a raya.", "Baja y sube, una y otra vez.",
                                "Una estela de pompas.", "Saca monedas de la nada.", "Tira: puede pasar cualquier cosa.",
                                "Se abre y trae una fortuna.", "Agítala: nieva.", "¡Flash! Una foto."])
        case .ptBR:
            return .init(items: ["Boné de hélice", "Papagaio de ombro", "Sapatos de mola", "Skate", "Guarda-chuva", "Ioiô",
                                 "Bolhas de sabão", "Ímã", "Dados da sorte", "Biscoito da sorte", "Globo de neve",
                                 "Câmera instantânea"],
                         gags: ["Gira e decola um instante.", "Grita e repete o que ouve.", "Cada passo, um pulo.",
                                "Ollies e kickflips.", "A própria chuva, longe.", "Desce e sobe, sem parar.",
                                "Um rastro de bolhas.", "Tira moedas do nada.", "Rola: tudo pode acontecer.",
                                "Abre e traz uma sorte.", "Sacuda: neva.", "Flash! Uma foto."])
        case .de:
            return .init(items: ["Propellermütze", "Schulterpapagei", "Sprungfederschuhe", "Skateboard", "Regenschirm", "Jo-Jo",
                                 "Seifenblasenstab", "Magnet", "Glückswürfel", "Glückskeks", "Schneekugel", "Sofortbildkamera"],
                         gags: ["Dreht auf und hebt kurz ab.", "Krächzt und plappert nach.", "Jeder Schritt ein Hüpfer.",
                                "Ollies und Kickflips.", "Der eigene Regen bleibt draußen.", "Runter und rauf, immer wieder.",
                                "Eine Spur aus Seifenblasen.", "Zieht Münzen aus dem Nichts.", "Ein Wurf: alles ist möglich.",
                                "Bricht auf und bringt ein Orakel.", "Schütteln: es schneit.", "Blitz! Ein Schnappschuss."])
        case .fr:
            return .init(items: ["Casquette à hélice", "Perroquet d’épaule", "Chaussures à ressort", "Skateboard", "Parapluie",
                                 "Yo-yo", "Bulles de savon", "Aimant", "Dés porte-bonheur", "Biscuit chinois",
                                 "Boule à neige", "Appareil instantané"],
                         gags: ["Tourne et décolle un instant.", "Crie et répète ce qu’il entend.", "Chaque pas, un rebond.",
                                "Ollies et kickflips.", "Sa propre pluie, tenue à l’écart.", "Descend et remonte, encore.",
                                "Une traînée de bulles.", "Attire des pièces de nulle part.", "Un lancer : tout peut arriver.",
                                "S’ouvre sur une prédiction.", "Secouez-la : il neige.", "Flash ! Une photo."])
        case .it:
            return .init(items: ["Cappello a elica", "Pappagallo da spalla", "Scarpe a molla", "Skateboard", "Ombrello", "Yo-yo",
                                 "Bolle di sapone", "Calamita", "Dadi fortunati", "Biscotto della fortuna", "Palla di neve",
                                 "Fotocamera istantanea"],
                         gags: ["Gira e decolla un attimo.", "Strilla e ripete ciò che sente.", "Ogni passo, un balzo.",
                                "Ollie e kickflip.", "La sua pioggia, tenuta lontana.", "Giù e su, ancora e ancora.",
                                "Una scia di bolle.", "Attira monete dal nulla.", "Un tiro: può succedere di tutto.",
                                "Si apre e porta una profezia.", "Agitala: nevica.", "Flash! Una foto."])
        case .sk:
            return .init(items: ["Čiapka s vrtuľkou", "Papagáj na pleci", "Pružinové topánky", "Skateboard", "Dáždnik", "Jojo",
                                 "Bublifuk", "Magnet", "Šťastné kocky", "Koláčik šťastia", "Snežná guľa", "Instantný fotoaparát"],
                         gags: ["Roztočí sa a na chvíľu vzlietne.", "Kriční a opakuje, čo počuje.", "Každý krok poskok.",
                                "Ollie a kickflipy.", "Vlastný dážď drží bokom.", "Dolu a hore, stále dokola.",
                                "Stopa z bublín.", "Priťahuje mince odnikiaľ.", "Hod: stať sa môže čokoľvek.",
                                "Rozlomí sa a prinesie veštbu.", "Zatras ňou: sneží.", "Blesk! Fotka."])
        case .uk:
            return .init(items: ["Кепка з пропелером", "Папуга на плечі", "Черевики на пружинах", "Скейтборд", "Парасолька",
                                 "Йо-йо", "Мильні бульбашки", "Магніт", "Щасливі кубики", "Печиво з передбаченням",
                                 "Сніжна куля", "Миттєва камера"],
                         gags: ["Розкручується й на мить злітає.", "Кричить і повторює почуте.", "Кожен крок — стрибок.",
                                "Олі та кікфліпи.", "Свій дощик — осторонь.", "Вниз і вгору, знову й знову.",
                                "Слід із бульбашок.", "Притягує монети нізвідки.", "Кидок: може статися що завгодно.",
                                "Розламується й дарує передбачення.", "Струсніть — іде сніг.", "Спалах! Знімок."])
        case .ru:
            return .init(items: ["Кепка с пропеллером", "Попугай на плече", "Ботинки на пружинах", "Скейтборд", "Зонтик",
                                 "Йо-йо", "Мыльные пузыри", "Магнит", "Счастливые кубики", "Печенье с предсказанием",
                                 "Снежный шар", "Моментальная камера"],
                         gags: ["Раскручивается и на миг взлетает.", "Кричит и повторяет услышанное.", "Каждый шаг — прыжок.",
                                "Олли и кикфлипы.", "Свой дождик — в стороне.", "Вниз и вверх, снова и снова.",
                                "След из пузырей.", "Притягивает монеты из ниоткуда.", "Бросок: может случиться что угодно.",
                                "Разламывается и дарит предсказание.", "Встряхните — идёт снег.", "Вспышка! Снимок."])
        case .tr:
            return .init(items: ["Pervaneli şapka", "Omuz papağanı", "Yaylı ayakkabılar", "Kaykay", "Şemsiye", "Yo-yo",
                                 "Baloncuk çubuğu", "Mıknatıs", "Şans zarları", "Şans kurabiyesi", "Kar küresi",
                                 "Şipşak makine"],
                         gags: ["Döner ve bir an havalanır.", "Bağırır, duyduğunu tekrarlar.", "Her adım bir zıplayış.",
                                "Ollie ve kickflip.", "Kendi yağmuru uzakta.", "Aşağı ve yukarı, durmadan.",
                                "Bir baloncuk izi.", "Yoktan para çeker.", "Bir atış: her şey olabilir.",
                                "Kırılır, bir kehanet çıkar.", "Salla: kar yağar.", "Flaş! Bir kare."])
        case .ja:
            return .init(items: ["プロペラ帽子", "肩のオウム", "バネぐつ", "スケートボード", "かさ", "ヨーヨー",
                                 "シャボン玉", "磁石", "幸運のサイコロ", "フォーチュンクッキー", "スノードーム", "インスタントカメラ"],
                         gags: ["くるくる回って少し浮かぶ。", "鳴いて聞いた言葉をまねる。", "一歩ごとにぴょん。",
                                "オーリーとキックフリップ。", "自分だけの雨をよける。", "下りて上がって、何度でも。",
                                "ふわふわ漂うシャボン玉。", "どこからかコインを引き寄せる。", "振れば何が起きるかわからない。",
                                "割ると占いが出てくる。", "振ると雪が降る。", "フラッシュ！ パシャリ。"])
        case .ko:
            return .init(items: ["프로펠러 모자", "어깨 앵무새", "스프링 신발", "스케이트보드", "우산", "요요",
                                 "비눗방울 막대", "자석", "행운의 주사위", "포춘 쿠키", "스노 글로브", "즉석 카메라"],
                         gags: ["빙글 돌며 잠깐 떠오릅니다.", "꽥꽥 울며 들은 말을 따라 합니다.", "걸음마다 통통.",
                                "올리와 킥플립.", "자기만의 비를 막아요.", "내려갔다 올라오기를 계속.",
                                "둥실 떠다니는 비눗방울.", "어디선가 동전을 끌어옵니다.", "던지면 무슨 일이든 일어나요.",
                                "쪼개면 운세가 나와요.", "흔들면 눈이 와요.", "번쩍! 찰칵."])
        case .zhHans:
            return .init(items: ["螺旋桨帽", "肩上鹦鹉", "弹簧鞋", "滑板", "雨伞", "悠悠球",
                                 "泡泡棒", "磁铁", "幸运骰子", "幸运饼干", "雪花水晶球", "拍立得相机"],
                         gags: ["转起来，飞一小会儿。", "叫几声，学你说话。", "每一步都弹一下。",
                                "豚跳加尖翻。", "替自己挡住小雨。", "下去又上来，一遍又一遍。",
                                "飘出一串泡泡。", "凭空吸来金币。", "一掷之下，什么都可能发生。",
                                "掰开就有一句签语。", "摇一摇，下雪了。", "闪光！咔嚓一张。"])
        case .zhTW:
            return .init(items: ["螺旋槳帽", "肩上鸚鵡", "彈簧鞋", "滑板", "雨傘", "溜溜球",
                                 "泡泡棒", "磁鐵", "幸運骰子", "幸運籤餅", "雪花水晶球", "拍立得相機"],
                         gags: ["轉起來，飛一小會兒。", "叫幾聲，學你說話。", "每一步都彈一下。",
                                "豚跳加尖翻。", "替自己擋住小雨。", "下去又上來，一遍又一遍。",
                                "飄出一串泡泡。", "憑空吸來金幣。", "一擲之下，什麼都可能發生。",
                                "掰開就有一句籤語。", "搖一搖，下雪了。", "閃光！喀嚓一張。"])
        case .zhHK:
            return .init(items: ["螺旋槳帽", "膊頭鸚鵡", "彈弓鞋", "滑板", "雨遮", "溜溜波",
                                 "泡泡棒", "磁石", "幸運骰仔", "幸運籤餅", "雪花水晶球", "即影即有相機"],
                         gags: ["轉吓轉，飛起一陣。", "叫幾聲，學你講嘢。", "每一步都彈一彈。",
                                "Ollie 加 kickflip。", "幫自己遮住細雨。", "落去又上返，一次又一次。",
                                "飄出一串泡泡。", "憑空吸啲金幣嚟。", "一擲之下，乜都有可能。",
                                "擘開就有句籤語。", "搖一搖，落雪喇。", "閃光！咔嚓一張。"])
        }
    }
}
