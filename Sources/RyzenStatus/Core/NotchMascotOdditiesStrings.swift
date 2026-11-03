// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The oddities and wonders: the names and a line on what each does, in the
/// order of `NotchMascotAccessory.oddityItems`.
struct NotchMascotOdditiesStrings {
    let items: [String]
    let gags: [String]

    static let itemCount = 16

    func name(of accessory: NotchMascotAccessory) -> String? {
        NotchMascotAccessory.oddityItems.firstIndex(of: accessory).map { items[$0] }
    }

    func gag(of accessory: NotchMascotAccessory) -> String? {
        NotchMascotAccessory.oddityItems.firstIndex(of: accessory).map { gags[$0] }
    }

    var isComplete: Bool {
        items.count == Self.itemCount && gags.count == Self.itemCount
            && items.allSatisfy { !$0.isEmpty } && gags.allSatisfy { !$0.isEmpty }
    }
}

extension FeatureStrings {
    // swiftlint:disable:next function_body_length
    static func notchMascotOddities(_ language: AppLanguage) -> NotchMascotOdditiesStrings {
        switch language {
        case .enUS:
            return .init(items: ["Pizza Slice", "Kazoo", "Bubble Gum", "Cracker Crown", "Rubber Chicken", "Pet Snail",
                                 "Jester Hat", "Snorkel and Mask", "Pirate Hook", "Feather Boa", "Roller Skates", "Lantern",
                                 "Wizard Beard", "Halo of Bees", "Spider Monocle", "UFO Hat"],
                         gags: ["The cheese stretches forever.", "A fanfare, badly out of tune.", "It grows, and grows… pop!",
                                "Bang! And a terrible joke inside.", "Bawk! Squeak! Bawk!", "A slow friend for slow walks.",
                                "Jingle, flip, and a cheeky grin.", "Swims through the air, blub blub.", "Arrr! Gold, please.",
                                "Simply fabulous, darling.", "Faster, faster… oof.", "Brave in the dark, until its shadow moves.",
                                "Stroked slowly while it thinks.", "The bees are not happy.", "Something looks back through the lens.",
                                "Beamed up, just a little."])
        case .es:
            return .init(items: ["Porción de pizza", "Kazoo", "Chicle", "Corona de papel", "Pollo de goma", "Caracol mascota",
                                 "Gorro de bufón", "Snorkel y máscara", "Garfio pirata", "Boa de plumas", "Patines", "Farol",
                                 "Barba de mago", "Aureola de abejas", "Monóculo con araña", "Sombrero OVNI"],
                         gags: ["El queso se estira sin fin.", "Una fanfarria bien desafinada.", "Crece, y crece… ¡plop!",
                                "¡Pum! Y adentro, un chiste malísimo.", "¡Coc! ¡Cuic! ¡Coc!", "Un amigo lento para paseos lentos.",
                                "Cascabeles, voltereta y sonrisa pícara.", "Nada por el aire, glu glu.", "¡Arrr! Oro, por favor.",
                                "Simplemente fabulosa, querida.", "Más rápido, más rápido… ¡paf!",
                                "Valiente en la oscuridad, hasta que se mueve su sombra.", "La acaricia despacio mientras piensa.",
                                "Las abejas no están contentas.", "Algo le devuelve la mirada por la lente.",
                                "Abducido, solo un poquito."])
        case .ptBR:
            return .init(items: ["Fatia de pizza", "Kazoo", "Chiclete", "Coroa de papel", "Galinha de borracha", "Caracol de estimação",
                                 "Chapéu de bobo da corte", "Snorkel e máscara", "Gancho pirata", "Boá de plumas", "Patins", "Lanterna",
                                 "Barba de mago", "Auréola de abelhas", "Monóculo com aranha", "Chapéu OVNI"],
                         gags: ["O queijo estica sem fim.", "Uma fanfarra bem desafinada.", "Cresce, e cresce… plop!",
                                "Bum! E uma piada péssima dentro.", "Có! Cuí! Có!", "Um amigo lento para passeios lentos.",
                                "Guizos, cambalhota e um sorriso maroto.", "Nada pelo ar, glub glub.", "Arrr! Ouro, por favor.",
                                "Simplesmente fabulosa, querida.", "Mais rápido, mais rápido… ai.",
                                "Corajoso no escuro, até a sombra se mexer.", "Afagada devagar enquanto pensa.",
                                "As abelhas não estão felizes.", "Algo olha de volta pela lente.", "Abduzido, só um pouquinho."])
        case .de:
            return .init(items: ["Pizzastück", "Kazoo", "Kaugummi", "Papierkrone", "Gummihuhn", "Haustier-Schnecke",
                                 "Narrenkappe", "Schnorchel und Maske", "Piratenhaken", "Federboa", "Rollschuhe", "Laterne",
                                 "Zauberbart", "Bienenheiligenschein", "Spinnenmonokel", "UFO-Hut"],
                         gags: ["Der Käse zieht sich ewig.", "Eine Fanfare, schief wie nie.", "Sie wächst und wächst… plopp!",
                                "Knall! Und drinnen ein schlechter Witz.", "Gack! Quietsch! Gack!", "Ein langsamer Freund für langsame Wege.",
                                "Glöckchen, Salto und ein freches Grinsen.", "Schwimmt durch die Luft, blubb blubb.",
                                "Arrr! Gold, bitte.", "Einfach fabelhaft, Schätzchen.", "Schneller, schneller… autsch.",
                                "Mutig im Dunkeln, bis sich der Schatten bewegt.", "Langsam gestreichelt beim Nachdenken.",
                                "Die Bienen sind nicht erfreut.", "Durch die Linse schaut etwas zurück.", "Ein bisschen hochgebeamt."])
        case .fr:
            return .init(items: ["Part de pizza", "Mirliton", "Chewing-gum", "Couronne en papier", "Poulet en caoutchouc",
                                 "Escargot de compagnie", "Bonnet de bouffon", "Tuba et masque", "Crochet de pirate", "Boa à plumes",
                                 "Patins à roulettes", "Lanterne", "Barbe de magicien", "Auréole d’abeilles", "Monocle à araignée",
                                 "Chapeau OVNI"],
                         gags: ["Le fromage file à l’infini.", "Une fanfare, terriblement fausse.", "Elle gonfle, gonfle… pop !",
                                "Pan ! Et une blague nulle dedans.", "Cot ! Couic ! Cot !", "Un ami lent pour des balades lentes.",
                                "Grelots, salto et sourire malicieux.", "Il nage dans les airs, blub blub.", "Arrr ! De l’or, svp.",
                                "Tout simplement fabuleux, chéri.", "Plus vite, plus vite… aïe.",
                                "Courageux dans le noir, jusqu’à ce que son ombre bouge.", "Caressée lentement pendant qu’il réfléchit.",
                                "Les abeilles ne sont pas contentes.", "Quelque chose le regarde à travers la lentille.",
                                "Téléporté, juste un peu."])
        case .it:
            return .init(items: ["Fetta di pizza", "Kazoo", "Gomma da masticare", "Corona di carta", "Pollo di gomma", "Lumachina",
                                 "Cappello da giullare", "Boccaglio e maschera", "Uncino da pirata", "Boa di piume", "Pattini a rotelle",
                                 "Lanterna", "Barba da mago", "Aureola di api", "Monocolo con ragno", "Cappello UFO"],
                         gags: ["Il formaggio si allunga all’infinito.", "Una fanfara, stonatissima.", "Cresce, cresce… pop!",
                                "Bang! E dentro una battuta pessima.", "Coccodè! Squit! Coccodè!", "Un amico lento per passeggiate lente.",
                                "Sonagli, capriola e un sorriso furbo.", "Nuota nell’aria, blub blub.", "Arrr! Oro, per favore.",
                                "Semplicemente favoloso, tesoro.", "Più veloce, più veloce… ahi.",
                                "Coraggioso al buio, finché l’ombra non si muove.", "Accarezzata piano mentre pensa.",
                                "Le api non sono contente.", "Qualcosa ricambia lo sguardo dalla lente.", "Teletrasportato, solo un po’."])
        case .sk:
            return .init(items: ["Kúsok pizze", "Kazoo", "Žuvačka", "Papierová koruna", "Gumové kura", "Slimák miláčik",
                                 "Šašovská čiapka", "Šnorchel a maska", "Pirátsky hák", "Pérové boa", "Kolieskové korčule", "Lampáš",
                                 "Čarodejnícka brada", "Svätožiara zo včiel", "Monokel s pavúkom", "Klobúk UFO"],
                         gags: ["Syr sa ťahá donekonečna.", "Fanfára, poriadne falošná.", "Rastie a rastie… puk!",
                                "Bum! A vnútri hrozný vtip.", "Kot! Pišt! Kot!", "Pomalý kamarát na pomalé prechádzky.",
                                "Rolničky, premet a šibalský úsmev.", "Pláva vzduchom, blub blub.", "Arrr! Zlato, prosím.",
                                "Jednoducho úžasné, zlatko.", "Rýchlejšie, rýchlejšie… au.",
                                "Odvážny v tme, kým sa nepohne jeho tieň.", "Pomaly hladká, keď premýšľa.",
                                "Včely nie sú nadšené.", "Cez šošovku sa niečo pozerá späť.", "Trochu unesený hore."])
        case .uk:
            return .init(items: ["Шматок піци", "Казу", "Жуйка", "Паперова корона", "Гумова курка", "Равлик-улюбленець",
                                 "Ковпак блазня", "Трубка й маска", "Піратський гак", "Пір’яне боа", "Роликові ковзани", "Ліхтар",
                                 "Борода чарівника", "Німб із бджіл", "Монокль із павуком", "Капелюх НЛО"],
                         gags: ["Сир тягнеться безкінечно.", "Фанфари, страшенно фальшиві.", "Росте, росте… пух!",
                                "Бах! А всередині жахливий жарт.", "Кво! Пі-пі! Кво!", "Повільний друг для повільних прогулянок.",
                                "Дзвоники, сальто й лукава усмішка.", "Пливе повітрям, буль-буль.", "Арр! Золото, будь ласка.",
                                "Просто розкішно, любчику.", "Швидше, швидше… ой.", "Сміливий у темряві, доки не ворухнеться тінь.",
                                "Повільно гладить, поки думає.", "Бджоли не в захваті.", "Крізь лінзу хтось дивиться у відповідь.",
                                "Трохи піднятий променем."])
        case .ru:
            return .init(items: ["Кусок пиццы", "Казу", "Жвачка", "Бумажная корона", "Резиновая курица", "Улитка-питомец",
                                 "Колпак шута", "Трубка и маска", "Пиратский крюк", "Перьевое боа", "Роликовые коньки", "Фонарь",
                                 "Борода волшебника", "Нимб из пчёл", "Монокль с пауком", "Шляпа НЛО"],
                         gags: ["Сыр тянется бесконечно.", "Фанфары, ужасно фальшивые.", "Растёт, растёт… пуф!",
                                "Бах! А внутри ужасная шутка.", "Ко! Пи-пи! Ко!", "Медленный друг для медленных прогулок.",
                                "Бубенцы, сальто и хитрая улыбка.", "Плывёт по воздуху, буль-буль.", "Арр! Золото, пожалуйста.",
                                "Просто восхитительно, дорогуша.", "Быстрее, быстрее… ой.",
                                "Смелый в темноте, пока не шевельнётся тень.", "Медленно гладит, пока думает.",
                                "Пчёлы недовольны.", "Сквозь линзу кто-то смотрит в ответ.", "Чуть-чуть похищен лучом."])
        case .tr:
            return .init(items: ["Pizza dilimi", "Kazu", "Sakız", "Kâğıt taç", "Lastik tavuk", "Evcil salyangoz",
                                 "Soytarı şapkası", "Şnorkel ve maske", "Korsan kancası", "Tüy boa", "Paten", "Fener",
                                 "Büyücü sakalı", "Arı halesi", "Örümcekli monokl", "UFO şapka"],
                         gags: ["Peynir bitmeden uzuyor.", "Bir fanfar, epey falso.", "Büyüyor, büyüyor… pat!",
                                "Bam! İçinde de berbat bir şaka.", "Gıt! Vık! Gıt!", "Yavaş yürüyüşler için yavaş bir dost.",
                                "Çıngırak, takla ve muzip bir sırıtış.", "Havada yüzüyor, blup blup.", "Arrr! Altın lütfen.",
                                "Düpedüz muhteşem, şekerim.", "Daha hızlı, daha hızlı… ah.", "Karanlıkta cesur, gölgesi kıpırdayana dek.",
                                "Düşünürken yavaşça sıvazlıyor.", "Arılar hiç memnun değil.", "Mercekten bir şey geri bakıyor.",
                                "Azıcık ışınlandı."])
        case .ja:
            return .init(items: ["ピザ一切れ", "カズー", "風船ガム", "紙の王冠", "ゴムのニワトリ", "ペットのカタツムリ",
                                 "道化師の帽子", "シュノーケルとマスク", "海賊のフック", "羽根のボア", "ローラースケート", "ランタン",
                                 "魔法使いのひげ", "ハチの輪", "クモ付きモノクル", "UFOハット"],
                         gags: ["チーズがどこまでも伸びる。", "ひどく音程の外れたファンファーレ。", "ふくらんで、ふくらんで…パン！",
                                "パン！中にはひどいジョーク。", "コケッ！キュッ！コケッ！", "のんびり散歩ののんびりな友だち。",
                                "鈴とバク転と、いたずらな笑み。", "空中をすいすい、ぶくぶく。", "アー！金貨をくれ。",
                                "とにかくゴージャスよ、あなた。", "もっと速く、もっと速く…いてっ。", "暗闇でも勇敢、影が動くまでは。",
                                "考えながらゆっくりなでる。", "ハチはご機嫌ななめ。", "レンズの向こうから何かが見返す。",
                                "ちょっとだけ吸い上げられる。"])
        case .ko:
            return .init(items: ["피자 조각", "카주", "풍선껌", "종이 왕관", "고무 닭", "애완 달팽이",
                                 "광대 모자", "스노클과 마스크", "해적 갈고리", "깃털 보아", "롤러스케이트", "랜턴",
                                 "마법사 수염", "벌 후광", "거미 외알 안경", "UFO 모자"],
                         gags: ["치즈가 끝없이 늘어나요.", "음이 한참 엇나간 팡파르.", "커지고, 커지고… 펑!",
                                "펑! 안에는 썰렁한 농담.", "꼬꼬! 삑! 꼬꼬!", "느린 산책을 위한 느린 친구.",
                                "방울, 공중제비, 장난스러운 미소.", "공중을 헤엄쳐요, 뽀글뽀글.", "아르르! 금화 주세요.",
                                "그냥 근사해, 자기야.", "더 빨리, 더 빨리… 아야.", "어둠 속에서도 용감해요, 그림자가 움직이기 전까진.",
                                "생각하며 천천히 쓰다듬어요.", "벌들이 화났어요.", "렌즈 너머에서 뭔가 마주 봐요.",
                                "아주 살짝 빔에 끌려 올라가요."])
        case .zhHans:
            return .init(items: ["披萨片", "卡祖笛", "泡泡糖", "纸皇冠", "橡胶鸡", "宠物蜗牛",
                                 "小丑帽", "潜水镜和呼吸管", "海盗钩", "羽毛围巾", "旱冰鞋", "提灯",
                                 "巫师胡子", "蜜蜂光环", "蜘蛛单片镜", "飞碟帽"],
                         gags: ["芝士拉得没完没了。", "一段走调的号角。", "越吹越大……啪！", "砰！里面还有个冷笑话。",
                                "咯！吱！咯！", "慢慢散步的慢朋友。", "铃铛、空翻和坏笑。", "在空中游泳，咕噜咕噜。",
                                "啊哈！请给金币。", "简直美极了，亲爱的。", "快点，再快点……哎哟。", "在黑暗中很勇敢，直到影子动了。",
                                "一边思考一边慢慢捋。", "蜜蜂很不高兴。", "镜片后面有东西在回看。", "被光束吸起来一点点。"])
        case .zhTW:
            return .init(items: ["披薩片", "卡祖笛", "泡泡糖", "紙皇冠", "橡膠雞", "寵物蝸牛",
                                 "小丑帽", "潛水鏡和呼吸管", "海盜鉤", "羽毛圍巾", "溜冰鞋", "提燈",
                                 "巫師鬍子", "蜜蜂光環", "蜘蛛單片眼鏡", "飛碟帽"],
                         gags: ["起司拉得沒完沒了。", "一段走音的號角。", "越吹越大……啪！", "砰！裡面還有個冷笑話。",
                                "咯！吱！咯！", "慢慢散步的慢朋友。", "鈴鐺、空翻和壞笑。", "在空中游泳，咕嚕咕嚕。",
                                "啊哈！請給金幣。", "簡直美極了，親愛的。", "快點，再快點……哎喲。", "在黑暗中很勇敢，直到影子動了。",
                                "一邊思考一邊慢慢捋。", "蜜蜂很不高興。", "鏡片後面有東西在回看。", "被光束吸起來一點點。"])
        case .zhHK:
            return .init(items: ["薄餅片", "卡祖笛", "香口膠", "紙皇冠", "橡膠雞", "寵物蝸牛",
                                 "小丑帽", "潛水鏡同呼吸管", "海盜鈎", "羽毛頸巾", "雪屐", "燈籠",
                                 "巫師鬚", "蜜蜂光環", "蜘蛛單片眼鏡", "飛碟帽"],
                         gags: ["芝士拉極都未斷。", "一段走晒音嘅號角。", "越吹越大……啪！", "嘭！入面仲有個冷笑話。",
                                "咯！吱！咯！", "慢慢行嘅慢朋友。", "鈴鐺、空翻同奸笑。", "喺半空游水，咕嚕咕嚕。",
                                "啊哈！畀啲金幣嚟。", "簡直靚到不得了，親愛的。", "快啲，再快啲……哎呀。", "喺黑暗入面好勇敢，直至影郁咗。",
                                "一路諗嘢一路慢慢掃。", "蜜蜂好唔開心。", "鏡片後面有嘢望返轉頭。", "俾光束吸起少少。"])
        }
    }
}
