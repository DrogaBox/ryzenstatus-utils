// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The Wonder Boy side of the companion in words: the thirty-two new
/// wearables, the secret doors, the abilities and the Pocket Card. Lists are
/// in the order of `NotchMascotAccessory.rpgItems`, `WonderBoySecretDoor.allCases`,
/// `NotchMascotAbility.allCases` and `HUD`.
struct NotchMascotRPGStrings {
    let accessories: [String]
    /// Arms, wear, magic, food and gadgets, in that order.
    let families: [String]
    let doors: [String]
    let doorDetails: [String]
    let abilities: [String]
    let hud: [String]

    /// The Pocket Card's and Settings' texts, by position in `hud`.
    enum HUD: Int {
        case pocketCard, hearts, vitality, gold, form, combo, noCombo, throwFruit, secretDoor, runCombo, changeGear
        case close, hungry, testCombo, synergiesFound, leader, friend, tavernHint, noFriend, noAbility
    }

    func text(_ item: HUD) -> String { hud[item.rawValue] }

    func synergiesFound(_ found: Int, of total: Int) -> String {
        String(format: text(.synergiesFound), found, total)
    }

    func tavernHint(_ name: String) -> String { String(format: text(.tavernHint), name) }

    /// The name of one of the thirty-two, or nil for the first eighteen.
    func name(of accessory: NotchMascotAccessory) -> String? {
        guard let index = NotchMascotAccessory.rpgItems.firstIndex(of: accessory) else { return nil }
        return accessories[index]
    }

    /// What kind of thing it is, in words.
    func detail(of accessory: NotchMascotAccessory) -> String? {
        guard accessory.isRPGItem else { return nil }
        let family: Int
        switch accessory {
        case .legendSword, .legendShield, .katana, .rangerBow, .kingScepter, .boomerang: family = 0
        case .wingBoots, .knightHelm, .vikingHelm, .sleepMask, .pacifier, .angelWings: family = 1
        case .wizardStaff, .magicTome, .crystalOrb, .fireballSpell, .tornadoSpell, .thunderTalisman,
             .heartPotion: family = 2
        case .iceCreamCone, .onigiri, .ramenBowl, .bobaTea: family = 3
        default: family = 4
        }
        return families[family]
    }

    func name(of door: WonderBoySecretDoor) -> String {
        doors[WonderBoySecretDoor.allCases.firstIndex(of: door) ?? 0]
    }

    func detail(of door: WonderBoySecretDoor) -> String {
        doorDetails[WonderBoySecretDoor.allCases.firstIndex(of: door) ?? 0]
    }

    func name(of ability: NotchMascotAbility) -> String {
        abilities[NotchMascotAbility.allCases.firstIndex(of: ability) ?? 0]
    }

    /// The counts every language must keep.
    static let accessoryCount = 32
    static let familyCount = 5
    static let doorCount = 5
    static let abilityCount = 5
    static let hudCount = 20

    var isComplete: Bool {
        accessories.count == Self.accessoryCount && families.count == Self.familyCount
            && doors.count == Self.doorCount && doorDetails.count == Self.doorCount
            && abilities.count == Self.abilityCount && hud.count == Self.hudCount
    }
}

extension FeatureStrings {
    static func notchMascotRPG(_ language: AppLanguage) -> NotchMascotRPGStrings {
        switch language {
        case .enUS: return NotchMascotRPGStrings(
            accessories: ["Hero Sword", "Hero Shield", "Winged Boots", "Knight Helm", "Katana", "Viking Helm", "Wizard Staff",
                          "Magic Tome", "Crystal Orb", "Ranger Bow", "King's Scepter", "Boomerang", "Fireball Spell",
                          "Tornado Spell", "Thunder Talisman", "Golden Key", "Hourglass", "Heart Potion", "Gold Bag",
                          "Ice Cream Cone", "Onigiri", "Ramen Bowl", "Boba Tea", "Sleep Mask", "Pacifier", "Bard's Lute",
                          "Dumbbells", "Detective Lens", "Laser Visor", "Jetpack", "Game Controller", "Angel Wings"],
            families: ["A weapon for duels and combos.", "Worn on the head, face, back or feet.",
                       "Magic that lights up combos.", "A snack for banquets: it fills the hourglass.",
                       "A gadget or treasure for exploring."],
            doors: ["Weapons & Winged Boots Shop", "Inn", "Monster Land Tavern", "Wizard's Hut", "Boss Lair"],
            doorDetails: ["Quicker steps for a while.", "A short rest: hearts and hourglass full.",
                          "A toast, and a hint of a combo not found yet.", "Arcane smoke; weapons leave trails.",
                          "A quick fight behind the camera, and a chest."],
            abilities: ["Ceiling walk", "Fireball breath", "Glide", "Dolphin dive", "Pepelogoo springboard"],
            hud: ["Pocket Card", "HEARTS", "VITALITY", "GOLD", "Class", "Combo", "No combo for this pair yet",
                  "Throw fruit", "Secret door", "Run combo", "Change gear", "Close", "Hungry", "Test combo",
                  "Synergies discovered: %d / %d", "Companion", "Friend", "Hint: %@",
                  "Pick a friend in Settings to see combos", "No special ability"])
        case .es: return NotchMascotRPGStrings(
            accessories: ["Espada del héroe", "Escudo del héroe", "Botas aladas", "Yelmo de caballero", "Katana",
                          "Casco vikingo", "Báculo de mago", "Tomo mágico", "Orbe de cristal", "Arco de arquero",
                          "Cetro del rey", "Bumerán", "Hechizo de bola de fuego", "Hechizo de tornado",
                          "Talismán del trueno", "Llave dorada", "Reloj de arena", "Poción de corazón", "Bolsa de oro",
                          "Cucurucho de helado", "Onigiri", "Cuenco de ramen", "Té de boba", "Antifaz de dormir",
                          "Chupete", "Laúd de bardo", "Mancuernas", "Lupa de detective", "Visor láser", "Jetpack",
                          "Mando de juegos", "Alas de ángel"],
            families: ["Un arma para duelos y combos.", "Se lleva en la cabeza, la cara, la espalda o los pies.",
                       "Magia que enciende los combos.", "Un bocado para banquetes: llena el reloj de arena.",
                       "Un artilugio o tesoro para explorar."],
            doors: ["Tienda de armas y botas aladas", "Posada", "Taberna de Monster Land", "Choza del mago",
                    "Guarida del jefe"],
            doorDetails: ["Pasos más rápidos un rato.", "Un descanso corto: corazones y reloj llenos.",
                          "Un brindis y una pista de un combo por descubrir.", "Humo arcano; las armas dejan estelas.",
                          "Un combate rápido tras la cámara y un cofre."],
            abilities: ["Caminar por el techo", "Aliento de fuego", "Planeo", "Zambullida de delfín",
                        "Trampolín de Pepelogoo"],
            hud: ["Tarjeta de bolsillo", "CORAZONES", "VITALIDAD", "ORO", "Clase", "Combo", "Aún sin combo para esta pareja",
                  "Lanzar fruta", "Puerta secreta", "Ejecutar combo", "Cambiar equipo", "Cerrar", "Hambre",
                  "Probar combo", "Sinergias descubiertas: %d / %d", "Compañero", "Amigo", "Pista: %@",
                  "Elige un amigo en Ajustes para ver combos", "Sin habilidad especial"])
        case .ptBR: return NotchMascotRPGStrings(
            accessories: ["Espada do herói", "Escudo do herói", "Botas aladas", "Elmo de cavaleiro", "Katana",
                          "Elmo viking", "Cajado de mago", "Tomo mágico", "Orbe de cristal", "Arco de arqueiro",
                          "Cetro do rei", "Bumerangue", "Feitiço de bola de fogo", "Feitiço de tornado",
                          "Talismã do trovão", "Chave dourada", "Ampulheta", "Poção de coração", "Bolsa de ouro",
                          "Casquinha de sorvete", "Onigiri", "Tigela de lámen", "Chá de boba", "Máscara de dormir",
                          "Chupeta", "Alaúde de bardo", "Halteres", "Lupa de detetive", "Visor laser", "Jetpack",
                          "Controle de jogo", "Asas de anjo"],
            families: ["Uma arma para duelos e combos.", "Usado na cabeça, no rosto, nas costas ou nos pés.",
                       "Magia que acende os combos.", "Um lanche para banquetes: enche a ampulheta.",
                       "Um gadget ou tesouro para explorar."],
            doors: ["Loja de armas e botas aladas", "Pousada", "Taverna de Monster Land", "Cabana do mago",
                    "Covil do chefe"],
            doorDetails: ["Passos mais rápidos por um tempo.", "Um descanso curto: corações e ampulheta cheios.",
                          "Um brinde e uma dica de um combo ainda não achado.", "Fumaça arcana; as armas deixam rastros.",
                          "Uma luta rápida atrás da câmera e um baú."],
            abilities: ["Andar no teto", "Sopro de fogo", "Planar", "Mergulho de golfinho", "Trampolim do Pepelogoo"],
            hud: ["Cartão de bolso", "CORAÇÕES", "VITALIDADE", "OURO", "Classe", "Combo", "Ainda sem combo para este par",
                  "Jogar fruta", "Porta secreta", "Executar combo", "Trocar equipamento", "Fechar", "Fome",
                  "Testar combo", "Sinergias descobertas: %d / %d", "Companheiro", "Amigo", "Dica: %@",
                  "Escolha um amigo nos Ajustes para ver combos", "Sem habilidade especial"])
        case .tr: return NotchMascotRPGStrings(
            accessories: ["Kahraman Kılıcı", "Kahraman Kalkanı", "Kanatlı Çizmeler", "Şövalye Miğferi", "Katana",
                          "Viking Miğferi", "Büyücü Asası", "Büyülü Kitap", "Kristal Küre", "Okçu Yayı", "Kralın Asası",
                          "Bumerang", "Ateş Topu Büyüsü", "Kasırga Büyüsü", "Gök Gürültüsü Tılsımı", "Altın Anahtar",
                          "Kum Saati", "Kalp İksiri", "Altın Kese", "Dondurma Külahı", "Onigiri", "Ramen Kasesi",
                          "Boba Çayı", "Uyku Maskesi", "Emzik", "Ozan Udu", "Dambıl", "Dedektif Merceği", "Lazer Vizör",
                          "Jetpack", "Oyun Kolu", "Melek Kanatları"],
            families: ["Düellolar ve kombolar için bir silah.", "Kafaya, yüze, sırta veya ayaklara takılır.",
                       "Kombolara ışık tutan büyü.", "Ziyafetler için atıştırmalık: kum saatini doldurur.",
                       "Keşif için bir alet veya hazine."],
            doors: ["Silah ve Kanatlı Çizme Dükkânı", "Han", "Monster Land Meyhanesi", "Büyücünün Kulübesi",
                    "Patron İni"],
            doorDetails: ["Bir süre daha hızlı adımlar.", "Kısa bir mola: kalpler ve kum saati dolu.",
                          "Bir kadeh ve henüz bulunmamış bir kombonun ipucu.", "Gizemli duman; silahlar iz bırakır.",
                          "Kameranın ardında hızlı bir dövüş ve bir sandık."],
            abilities: ["Tavanda yürüme", "Ateş topu nefesi", "Süzülme", "Yunus dalışı", "Pepelogoo sıçrama tahtası"],
            hud: ["Cep Kartı", "KALPLER", "CANLILIK", "ALTIN", "Sınıf", "Kombo", "Bu çift için henüz kombo yok",
                  "Meyve at", "Gizli kapı", "Komboyu çalıştır", "Ekipmanı değiştir", "Kapat", "Aç", "Komboyu dene",
                  "Keşfedilen sinerjiler: %d / %d", "Yoldaş", "Arkadaş", "İpucu: %@",
                  "Komboları görmek için Ayarlar'dan bir arkadaş seç", "Özel yetenek yok"])
        case .ru: return NotchMascotRPGStrings(
            accessories: ["Меч героя", "Щит героя", "Крылатые сапоги", "Шлем рыцаря", "Катана", "Шлем викинга",
                          "Посох мага", "Магический том", "Хрустальный шар", "Лук следопыта", "Скипетр короля",
                          "Бумеранг", "Заклинание огненного шара", "Заклинание торнадо", "Талисман грома",
                          "Золотой ключ", "Песочные часы", "Зелье сердца", "Мешок золота", "Рожок мороженого",
                          "Онигири", "Миска рамэна", "Чай с боба", "Маска для сна", "Пустышка", "Лютня барда",
                          "Гантели", "Лупа сыщика", "Лазерный визор", "Реактивный ранец", "Геймпад", "Крылья ангела"],
            families: ["Оружие для дуэлей и комбо.", "Надевается на голову, лицо, спину или ноги.",
                       "Магия, зажигающая комбо.", "Закуска для пиршеств: наполняет песочные часы.",
                       "Устройство или сокровище для исследований."],
            doors: ["Лавка оружия и крылатых сапог", "Постоялый двор", "Таверна Monster Land", "Хижина мага",
                    "Логово босса"],
            doorDetails: ["Шаги быстрее на время.", "Недолгий отдых: сердца и часы полны.",
                          "Тост и подсказка о ненайденном комбо.", "Тайный дым; оружие оставляет шлейфы.",
                          "Быстрый бой за камерой и сундук."],
            abilities: ["Ходьба по потолку", "Огненное дыхание", "Планирование", "Прыжок дельфина",
                        "Трамплин Пепелогу"],
            hud: ["Карманная карта", "СЕРДЦА", "ЖИЗНЕННОСТЬ", "ЗОЛОТО", "Класс", "Комбо", "Для этой пары комбо пока нет",
                  "Бросить фрукт", "Тайная дверь", "Запустить комбо", "Сменить снаряжение", "Закрыть", "Голод",
                  "Проверить комбо", "Найдено синергий: %d / %d", "Спутник", "Друг", "Подсказка: %@",
                  "Выберите друга в настройках, чтобы увидеть комбо", "Нет особого умения"])
        case .de: return NotchMascotRPGStrings(
            accessories: ["Heldenschwert", "Heldenschild", "Flügelstiefel", "Ritterhelm", "Katana", "Wikingerhelm",
                          "Zauberstab", "Zauberbuch", "Kristallkugel", "Waldläuferbogen", "Zepter des Königs",
                          "Bumerang", "Feuerballzauber", "Tornadozauber", "Donnertalisman", "Goldener Schlüssel",
                          "Sanduhr", "Herztrank", "Goldbeutel", "Eiswaffel", "Onigiri", "Ramen-Schüssel", "Boba-Tee",
                          "Schlafmaske", "Schnuller", "Laute des Barden", "Hanteln", "Detektivlupe", "Laservisier",
                          "Jetpack", "Spielcontroller", "Engelsflügel"],
            families: ["Eine Waffe für Duelle und Kombos.", "Wird auf Kopf, Gesicht, Rücken oder Füßen getragen.",
                       "Magie, die Kombos zum Leuchten bringt.", "Ein Snack für Festmähler: füllt die Sanduhr.",
                       "Ein Gadget oder Schatz zum Erkunden."],
            doors: ["Waffen- & Flügelstiefel-Laden", "Gasthaus", "Taverne von Monster Land", "Hütte des Magiers",
                    "Bosshöhle"],
            doorDetails: ["Eine Weile schnellere Schritte.", "Kurze Rast: Herzen und Sanduhr voll.",
                          "Ein Prost und ein Hinweis auf eine unentdeckte Kombo.", "Arkaner Rauch; Waffen ziehen Spuren.",
                          "Ein kurzer Kampf hinter der Kamera und eine Truhe."],
            abilities: ["Deckenlauf", "Feuerball-Atem", "Gleitflug", "Delfinsprung", "Pepelogoo-Sprungbrett"],
            hud: ["Taschenkarte", "HERZEN", "VITALITÄT", "GOLD", "Klasse", "Kombo", "Für dieses Paar noch keine Kombo",
                  "Obst werfen", "Geheimtür", "Kombo starten", "Ausrüstung wechseln", "Schließen", "Hunger",
                  "Kombo testen", "Entdeckte Synergien: %d / %d", "Begleiter", "Freund", "Hinweis: %@",
                  "Wähle in den Einstellungen einen Freund, um Kombos zu sehen", "Keine besondere Fähigkeit"])
        case .fr: return NotchMascotRPGStrings(
            accessories: ["Épée du héros", "Bouclier du héros", "Bottes ailées", "Heaume de chevalier", "Katana",
                          "Casque viking", "Bâton de mage", "Grimoire magique", "Orbe de cristal", "Arc de rôdeur",
                          "Sceptre du roi", "Boomerang", "Sort de boule de feu", "Sort de tornade",
                          "Talisman du tonnerre", "Clé dorée", "Sablier", "Potion de cœur", "Bourse d'or",
                          "Cornet de glace", "Onigiri", "Bol de ramen", "Thé aux perles", "Masque de sommeil", "Tétine",
                          "Luth de barde", "Haltères", "Loupe de détective", "Visière laser", "Jetpack",
                          "Manette de jeu", "Ailes d'ange"],
            families: ["Une arme pour les duels et les combos.", "Se porte sur la tête, le visage, le dos ou les pieds.",
                       "De la magie qui allume les combos.", "Une collation de banquet : elle remplit le sablier.",
                       "Un gadget ou un trésor pour explorer."],
            doors: ["Boutique d'armes et de bottes ailées", "Auberge", "Taverne de Monster Land", "Cabane du mage",
                    "Antre du boss"],
            doorDetails: ["Des pas plus rapides un moment.", "Un court repos : cœurs et sablier pleins.",
                          "Un toast et un indice sur un combo à trouver.", "Fumée arcanique ; les armes laissent des traînées.",
                          "Un combat éclair derrière la caméra et un coffre."],
            abilities: ["Marche au plafond", "Souffle de feu", "Plané", "Plongeon de dauphin", "Tremplin de Pepelogoo"],
            hud: ["Carte de poche", "CŒURS", "VITALITÉ", "OR", "Classe", "Combo", "Pas encore de combo pour ce duo",
                  "Lancer un fruit", "Porte secrète", "Lancer le combo", "Changer d'équipement", "Fermer", "Faim",
                  "Essayer le combo", "Synergies découvertes : %d / %d", "Compagnon", "Ami", "Indice : %@",
                  "Choisissez un ami dans les Réglages pour voir les combos", "Pas de capacité spéciale"])
        case .it: return NotchMascotRPGStrings(
            accessories: ["Spada dell'eroe", "Scudo dell'eroe", "Stivali alati", "Elmo da cavaliere", "Katana",
                          "Elmo vichingo", "Bastone da mago", "Tomo magico", "Sfera di cristallo", "Arco da ranger",
                          "Scettro del re", "Boomerang", "Incantesimo palla di fuoco", "Incantesimo tornado",
                          "Talismano del tuono", "Chiave d'oro", "Clessidra", "Pozione del cuore", "Sacchetto d'oro",
                          "Cono gelato", "Onigiri", "Ciotola di ramen", "Tè boba", "Mascherina per dormire", "Ciuccio",
                          "Liuto del bardo", "Manubri", "Lente da detective", "Visore laser", "Jetpack",
                          "Controller di gioco", "Ali d'angelo"],
            families: ["Un'arma per duelli e combo.", "Si indossa su testa, viso, schiena o piedi.",
                       "Magia che accende le combo.", "Uno spuntino da banchetto: riempie la clessidra.",
                       "Un gadget o un tesoro per esplorare."],
            doors: ["Negozio di armi e stivali alati", "Locanda", "Taverna di Monster Land", "Capanna del mago",
                    "Tana del boss"],
            doorDetails: ["Passi più veloci per un po'.", "Un breve riposo: cuori e clessidra pieni.",
                          "Un brindisi e un indizio su una combo da scoprire.", "Fumo arcano; le armi lasciano scie.",
                          "Un combattimento lampo dietro la fotocamera e uno scrigno."],
            abilities: ["Camminata sul soffitto", "Soffio di fuoco", "Planata", "Tuffo di delfino",
                        "Trampolino di Pepelogoo"],
            hud: ["Scheda tascabile", "CUORI", "VITALITÀ", "ORO", "Classe", "Combo", "Ancora nessuna combo per questa coppia",
                  "Lancia frutta", "Porta segreta", "Esegui combo", "Cambia equipaggiamento", "Chiudi", "Fame",
                  "Prova la combo", "Sinergie scoperte: %d / %d", "Compagno", "Amico", "Indizio: %@",
                  "Scegli un amico nelle Impostazioni per vedere le combo", "Nessuna abilità speciale"])
        case .ja: return NotchMascotRPGStrings(
            accessories: ["勇者の剣", "勇者の盾", "翼のブーツ", "騎士の兜", "刀", "バイキングの兜", "魔法使いの杖", "魔導書",
                          "水晶玉", "レンジャーの弓", "王の笏", "ブーメラン", "火球の呪文", "竜巻の呪文", "雷のお守り", "金の鍵",
                          "砂時計", "ハートのポーション", "金貨の袋", "アイスクリーム", "おにぎり", "ラーメン", "タピオカティー",
                          "アイマスク", "おしゃぶり", "吟遊詩人のリュート", "ダンベル", "探偵の虫眼鏡", "レーザーバイザー",
                          "ジェットパック", "ゲームコントローラー", "天使の翼"],
            families: ["決闘とコンボのための武器。", "頭・顔・背中・足に身につける。", "コンボを輝かせる魔法。",
                       "宴のおやつ。砂時計を満たす。", "探検のための道具や宝物。"],
            doors: ["武器と翼のブーツの店", "宿屋", "モンスターランドの酒場", "魔法使いの小屋", "ボスの巣"],
            doorDetails: ["しばらく足が速くなる。", "ひと休み：ハートと砂時計が満タンに。", "乾杯と、まだ見つけていないコンボのヒント。",
                          "秘術の煙。武器が軌跡を残す。", "カメラの裏での早業バトルと宝箱。"],
            abilities: ["天井歩き", "火球ブレス", "滑空", "イルカダイブ", "ペペロゴのトランポリン"],
            hud: ["ポケットカード", "ハート", "活力", "ゴールド", "クラス", "コンボ", "このペアのコンボはまだありません",
                  "果物を投げる", "秘密の扉", "コンボを実行", "装備を変える", "閉じる", "空腹", "コンボを試す",
                  "発見したシナジー：%d / %d", "コンパニオン", "友だち", "ヒント：%@",
                  "コンボを見るには設定で友だちを選んでください", "特別な能力なし"])
        case .ko: return NotchMascotRPGStrings(
            accessories: ["용사의 검", "용사의 방패", "날개 부츠", "기사 투구", "카타나", "바이킹 투구", "마법사 지팡이", "마법서",
                          "수정 구슬", "레인저 활", "왕의 홀", "부메랑", "화염구 주문", "토네이도 주문", "천둥 부적", "황금 열쇠",
                          "모래시계", "하트 물약", "금화 주머니", "아이스크림 콘", "오니기리", "라멘 그릇", "버블티", "수면 안대",
                          "젖꼭지", "음유시인의 류트", "덤벨", "탐정 돋보기", "레이저 바이저", "제트팩", "게임 컨트롤러",
                          "천사 날개"],
            families: ["결투와 콤보를 위한 무기.", "머리, 얼굴, 등, 발에 착용합니다.", "콤보를 밝혀 주는 마법.",
                       "연회용 간식: 모래시계를 채웁니다.", "탐험을 위한 도구나 보물."],
            doors: ["무기 & 날개 부츠 상점", "여관", "몬스터랜드 주점", "마법사의 오두막", "보스의 소굴"],
            doorDetails: ["잠시 동안 걸음이 빨라집니다.", "짧은 휴식: 하트와 모래시계가 가득 찹니다.",
                          "건배와 아직 찾지 못한 콤보의 힌트.", "비전의 연기. 무기가 궤적을 남깁니다.",
                          "카메라 뒤의 빠른 전투와 보물상자."],
            abilities: ["천장 걷기", "화염구 숨결", "활공", "돌고래 다이브", "페페로구 트램펄린"],
            hud: ["포켓 카드", "하트", "활력", "골드", "클래스", "콤보", "이 짝에게는 아직 콤보가 없습니다", "과일 던지기",
                  "비밀의 문", "콤보 실행", "장비 변경", "닫기", "배고픔", "콤보 시험", "발견한 시너지: %d / %d", "동료",
                  "친구", "힌트: %@", "콤보를 보려면 설정에서 친구를 고르세요", "특별한 능력 없음"])
        case .zhHans: return NotchMascotRPGStrings(
            accessories: ["勇者之剑", "勇者之盾", "飞翼靴", "骑士头盔", "太刀", "维京头盔", "法师法杖", "魔法书", "水晶球",
                          "游侠之弓", "国王权杖", "回旋镖", "火球咒语", "龙卷风咒语", "雷霆护符", "金钥匙", "沙漏", "爱心药水",
                          "金币袋", "冰淇淋甜筒", "饭团", "拉面碗", "珍珠奶茶", "睡眠眼罩", "安抚奶嘴", "吟游诗人鲁特琴",
                          "哑铃", "侦探放大镜", "激光面罩", "喷气背包", "游戏手柄", "天使之翼"],
            families: ["用于决斗和连招的武器。", "戴在头、脸、背或脚上。", "点亮连招的魔法。", "宴会小吃：能填满沙漏。",
                       "探索用的小玩意或宝物。"],
            doors: ["武器与飞翼靴商店", "旅店", "怪物乐园酒馆", "法师小屋", "头目巢穴"],
            doorDetails: ["短时间内步伐更快。", "短暂休息：爱心和沙漏回满。", "干杯，并提示一个尚未发现的连招。",
                          "奥术烟雾；武器会留下轨迹。", "镜头后的快速战斗，以及一个宝箱。"],
            abilities: ["天花板行走", "火球吐息", "滑翔", "海豚跃", "佩佩洛古蹦床"],
            hud: ["口袋卡", "爱心", "活力", "金币", "职业", "连招", "这一对还没有连招", "扔水果", "秘密之门", "执行连招",
                  "更换装备", "关闭", "饥饿", "试试连招", "已发现的协同：%d / %d", "伙伴", "朋友", "提示：%@",
                  "在设置中选择一位朋友以查看连招", "没有特殊能力"])
        case .zhTW, .zhHK: return NotchMascotRPGStrings(
            accessories: ["勇者之劍", "勇者之盾", "飛翼靴", "騎士頭盔", "太刀", "維京頭盔", "法師法杖", "魔法書", "水晶球",
                          "遊俠之弓", "國王權杖", "迴旋鏢", "火球咒語", "龍捲風咒語", "雷霆護符", "金鑰匙", "沙漏", "愛心藥水",
                          "金幣袋", "冰淇淋甜筒", "飯糰", "拉麵碗", "珍珠奶茶", "睡眠眼罩", "安撫奶嘴", "吟遊詩人魯特琴",
                          "啞鈴", "偵探放大鏡", "雷射面罩", "噴射背包", "遊戲手把", "天使之翼"],
            families: ["用於決鬥與連招的武器。", "戴在頭、臉、背或腳上。", "點亮連招的魔法。", "宴會小點：能填滿沙漏。",
                       "探索用的小玩意或寶物。"],
            doors: ["武器與飛翼靴商店", "旅店", "怪物樂園酒館", "法師小屋", "頭目巢穴"],
            doorDetails: ["短時間內步伐更快。", "短暫休息：愛心與沙漏回滿。", "乾杯，並提示一個尚未發現的連招。",
                          "奧術煙霧；武器會留下軌跡。", "鏡頭後的快速戰鬥，以及一個寶箱。"],
            abilities: ["天花板行走", "火球吐息", "滑翔", "海豚躍", "佩佩洛古蹦床"],
            hud: ["口袋卡", "愛心", "活力", "金幣", "職業", "連招", "這一對還沒有連招", "丟水果", "秘密之門", "執行連招",
                  "更換裝備", "關閉", "飢餓", "試試連招", "已發現的協同：%d / %d", "夥伴", "朋友", "提示：%@",
                  "在設定中選擇一位朋友以查看連招", "沒有特殊能力"])
        case .sk: return NotchMascotRPGStrings(
            accessories: ["Hrdinov meč", "Hrdinov štít", "Okrídlené čižmy", "Rytierska prilba", "Katana",
                          "Vikingská prilba", "Čarodejnícka palica", "Magická kniha", "Krištáľová guľa", "Lukostrelcov luk",
                          "Kráľovské žezlo", "Bumerang", "Kúzlo ohnivej gule", "Kúzlo tornáda", "Hromový talizman",
                          "Zlatý kľúč", "Presýpacie hodiny", "Srdcový elixír", "Vrecúško zlata", "Zmrzlinový kornút",
                          "Onigiri", "Miska ramenu", "Boba čaj", "Maska na spanie", "Cumlík", "Bardova lutna",
                          "Činky", "Detektívna lupa", "Laserový vizor", "Jetpack", "Herný ovládač", "Anjelské krídla"],
            families: ["Zbraň na súboje a kombá.", "Nosí sa na hlave, tvári, chrbte alebo nohách.",
                       "Mágia, ktorá rozsvieti kombá.", "Maškrta na hostiny: plní presýpacie hodiny.",
                       "Pomôcka alebo poklad na objavovanie."],
            doors: ["Obchod so zbraňami a okrídlenými čižmami", "Hostinec", "Krčma Monster Land",
                    "Čarodejníkova chatrč", "Brloh bossa"],
            doorDetails: ["Na chvíľu rýchlejšie kroky.", "Krátky odpočinok: srdcia a hodiny plné.",
                          "Prípitok a nápoveda k nenájdenému kombu.", "Tajomný dym; zbrane nechávajú stopy.",
                          "Rýchly súboj za kamerou a truhlica."],
            abilities: ["Chôdza po strope", "Dych ohnivej gule", "Klzanie", "Delfínový skok", "Pepelogoo trampolína"],
            hud: ["Vreckový lístok", "SRDCIA", "VITALITA", "ZLATO", "Trieda", "Kombo", "Pre tento pár zatiaľ nie je kombo",
                  "Hodiť ovocie", "Tajné dvere", "Spustiť kombo", "Zmeniť výbavu", "Zavrieť", "Hlad", "Vyskúšať kombo",
                  "Objavené synergie: %d / %d", "Spoločník", "Priateľ", "Nápoveda: %@",
                  "Vyberte priateľa v Nastaveniach a uvidíte kombá", "Žiadna zvláštna schopnosť"])
        case .uk: return NotchMascotRPGStrings(
            accessories: ["Меч героя", "Щит героя", "Крилаті чоботи", "Шолом лицаря", "Катана", "Шолом вікінга",
                          "Посох чарівника", "Магічний том", "Кришталева куля", "Лук слідопита", "Скіпетр короля",
                          "Бумеранг", "Заклинання вогняної кулі", "Заклинання торнадо", "Талісман грому", "Золотий ключ",
                          "Пісочний годинник", "Зілля серця", "Мішечок золота", "Ріжок морозива", "Онігірі",
                          "Миска раменю", "Чай боба", "Маска для сну", "Пустушка", "Лютня барда", "Гантелі",
                          "Лупа детектива", "Лазерний візор", "Реактивний ранець", "Геймпад", "Крила ангела"],
            families: ["Зброя для двобоїв і комбо.", "Одягається на голову, обличчя, спину чи ноги.",
                       "Магія, що запалює комбо.", "Перекус для бенкетів: наповнює пісочний годинник.",
                       "Пристрій або скарб для досліджень."],
            doors: ["Крамниця зброї та крилатих чобіт", "Корчма", "Таверна Monster Land", "Хатина чарівника",
                    "Лігво боса"],
            doorDetails: ["Швидші кроки на деякий час.", "Короткий відпочинок: серця й годинник повні.",
                          "Тост і підказка про незнайдене комбо.", "Таємничий дим; зброя лишає сліди.",
                          "Швидкий бій за камерою і скриня."],
            abilities: ["Ходьба по стелі", "Дихання вогнем", "Планування", "Стрибок дельфіна", "Трамплін Пепелогу"],
            hud: ["Кишенькова картка", "СЕРЦЯ", "ЖИТТЄВІСТЬ", "ЗОЛОТО", "Клас", "Комбо", "Для цієї пари комбо ще немає",
                  "Кинути фрукт", "Таємні двері", "Запустити комбо", "Змінити спорядження", "Закрити", "Голод",
                  "Спробувати комбо", "Знайдено синергій: %d / %d", "Супутник", "Друг", "Підказка: %@",
                  "Оберіть друга в налаштуваннях, щоб побачити комбо", "Немає особливого вміння"])
        }
    }
}
