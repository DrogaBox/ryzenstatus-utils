// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The words of the wardrobe browser and of the chain reactions card: the
/// search, the families, where a thing is worn, how the list is sorted,
/// what a thing does in a chain and the rare things a chain can set off.
struct NotchMascotWardrobeStrings {
    let search: String
    let all: String
    /// In the order of `NotchMascotWardrobeFamily`.
    let families: [String]
    /// In the order of `NotchMascotWardrobeSpot`: head, eyes, neck, hand, back, feet.
    let spots: [String]
    let owned: String
    let notOwned: String
    let sortTitle: String
    /// In the order of `NotchMascotWardrobeSort`: family, rarity, name, price.
    let sorts: [String]
    /// The badge on the lab and mayhem things.
    let newBadge: String
    let nothingMatches: String
    let clearFilters: String
    let expandAll: String
    let collapseAll: String
    /// "12 of 204": shown, then all there are.
    let shownFormat: String
    /// Who the wardrobe dresses: the companion or its friend.
    let dressing: String
    let wear: String
    let worn: String
    /// A thing that opens with a level rather than being bought.
    let levelReward: String
    let inShop: String
    let notInShop: String
    let shopForOther: String
    let throwsFormat: String
    let reactsFormat: String
    /// What it reacts to, then what it throws on.
    let reactsThrowsFormat: String
    let noChain: String
    /// In the order of `NotchMascotStimulus.allCases`, as read in the lines above.
    let stimuli: [String]
    let chainTitle: String
    let chainHint: String
    let foundFormat: String
    let raresTitle: String
    let unknownRare: String
    let rareGoldFormat: String
    let close: String
    let locked: String

    func family(_ family: NotchMascotWardrobeFamily) -> String { families[family.rawValue] }
    func spot(_ spot: NotchMascotWardrobeSpot) -> String { spots[spot.rawValue] }
    func sort(_ sort: NotchMascotWardrobeSort) -> String { sorts[sort.rawValue] }

    func stimulus(_ stimulus: NotchMascotStimulus) -> String {
        NotchMascotStimulus.allCases.firstIndex(of: stimulus).map { stimuli[$0] } ?? stimulus.rawValue
    }

    func shown(_ count: Int, of total: Int) -> String { String(format: shownFormat, "\(count)", "\(total)") }
    func throwsLine(_ stimulus: NotchMascotStimulus) -> String { String(format: throwsFormat, self.stimulus(stimulus)) }
    func reactsLine(_ stimulus: NotchMascotStimulus, then thrown: NotchMascotStimulus?) -> String {
        guard let thrown else { return String(format: reactsFormat, self.stimulus(stimulus)) }
        return String(format: reactsThrowsFormat, self.stimulus(stimulus), self.stimulus(thrown))
    }
    func found(_ count: Int) -> String { String(format: foundFormat, "\(count)") }
    func rareGold(_ gold: Int) -> String { String(format: rareGoldFormat, "\(gold)") }

    var isComplete: Bool {
        families.count == NotchMascotWardrobeFamily.allCases.count && spots.count == NotchMascotWardrobeSpot.allCases.count
            && sorts.count == NotchMascotWardrobeSort.allCases.count && stimuli.count == NotchMascotStimulus.allCases.count
    }
}

extension FeatureStrings {
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    static func notchMascotWardrobe(_ language: AppLanguage) -> NotchMascotWardrobeStrings {
        switch language {
        case .enUS:
            return .init(search: "Search by name", all: "All",
                         families: ["Level rewards", "Wonder Boy", "Curiosities", "Dance", "Toys & luck", "Party",
                                    "Oddities", "Workshop", "Fair & field", "The lab", "Mayhem"],
                         spots: ["Head", "Eyes", "Neck", "Hand", "Back", "Feet"],
                         owned: "Owned", notOwned: "Not owned", sortTitle: "Sort by",
                         sorts: ["Family", "Rarity", "Name", "Price"],
                         newBadge: "NEW", nothingMatches: "Nothing matches these filters.", clearFilters: "Clear filters",
                         expandAll: "Open all", collapseAll: "Close all", shownFormat: "%1$@ of %2$@",
                         dressing: "Dressing", wear: "Wear", worn: "Wearing it", levelReward: "Comes with a level",
                         inShop: "In the shop now",
                         notInShop: "Not in the shop now; a new stock may bring it.",
                         shopForOther: "In the shop now, but the shop is buying for another figure. Change who it buys for in the shop above.",
                         throwsFormat: "Throws %@", reactsFormat: "Reacts to %@",
                         reactsThrowsFormat: "Reacts to %1$@, then throws %2$@",
                         noChain: "Plays no part of its own in chain reactions: it takes them the plain way.",
                         stimuli: ["fire", "water", "wind", "a shock", "frost", "light", "sound", "pepper", "a bonk",
                                   "a magnet", "something sweet", "goo", "hypnosis", "a tickle"],
                         chainTitle: "Chain reactions",
                         chainHint: "One throws what it holds at the nearest friend, who makes something of it and maybe throws something on. Every reaction seen is kept here.",
                         foundFormat: "%@ found", raresTitle: "Rare events", unknownRare: "???", rareGoldFormat: "+%@ gold",
                         close: "Close", locked: "Locked")
        case .es:
            return .init(search: "Buscar por nombre", all: "Todo",
                         families: ["Premios de nivel", "Wonder Boy", "Curiosidades", "Danza", "Juguetes y suerte", "Fiesta",
                                    "Rarezas", "Taller", "Feria y campo", "El laboratorio", "Caos"],
                         spots: ["Cabeza", "Ojos", "Cuello", "Mano", "Espalda", "Pies"],
                         owned: "Lo tiene", notOwned: "No lo tiene", sortTitle: "Ordenar por",
                         sorts: ["Familia", "Rareza", "Nombre", "Precio"],
                         newBadge: "NUEVO", nothingMatches: "Nada coincide con estos filtros.", clearFilters: "Quitar filtros",
                         expandAll: "Abrir todo", collapseAll: "Cerrar todo", shownFormat: "%1$@ de %2$@",
                         dressing: "Vistiendo a", wear: "Ponérselo", worn: "Lo lleva puesto", levelReward: "Viene con un nivel",
                         inShop: "En la tienda ahora",
                         notInShop: "No está en la tienda ahora; un escaparate nuevo puede traerlo.",
                         shopForOther: "Está en la tienda, pero la tienda compra para otra figura. Cambia para quién compra en la tienda de arriba.",
                         throwsFormat: "Lanza %@", reactsFormat: "Reacciona a %@",
                         reactsThrowsFormat: "Reacciona a %1$@ y lanza %2$@",
                         noChain: "No tiene un papel propio en las reacciones en cadena: las recibe de la forma normal.",
                         stimuli: ["fuego", "agua", "viento", "una descarga", "escarcha", "luz", "sonido", "pimienta",
                                   "un golpe", "un imán", "algo dulce", "baba", "hipnosis", "cosquillas"],
                         chainTitle: "Reacciones en cadena",
                         chainHint: "Uno lanza lo que tiene al amigo más cercano, que hace algo con eso y quizá lanza algo más. Aquí queda cada reacción vista.",
                         foundFormat: "%@ descubiertas", raresTitle: "Sucesos raros", unknownRare: "???",
                         rareGoldFormat: "+%@ de oro", close: "Cerrar", locked: "Bloqueado")
        case .ptBR:
            return .init(search: "Buscar pelo nome", all: "Tudo",
                         families: ["Prêmios de nível", "Wonder Boy", "Curiosidades", "Dança", "Brinquedos e sorte", "Festa",
                                    "Esquisitices", "Oficina", "Feira e campo", "O laboratório", "Caos"],
                         spots: ["Cabeça", "Olhos", "Pescoço", "Mão", "Costas", "Pés"],
                         owned: "Tem", notOwned: "Não tem", sortTitle: "Ordenar por",
                         sorts: ["Família", "Raridade", "Nome", "Preço"],
                         newBadge: "NOVO", nothingMatches: "Nada combina com estes filtros.", clearFilters: "Limpar filtros",
                         expandAll: "Abrir tudo", collapseAll: "Fechar tudo", shownFormat: "%1$@ de %2$@",
                         dressing: "Vestindo", wear: "Usar", worn: "Está usando", levelReward: "Vem com um nível",
                         inShop: "Na loja agora",
                         notInShop: "Não está na loja agora; um estoque novo pode trazê-lo.",
                         shopForOther: "Está na loja, mas a loja compra para outra figura. Troque para quem ela compra na loja acima.",
                         throwsFormat: "Lança: %@", reactsFormat: "Reage a: %@",
                         reactsThrowsFormat: "Reage a: %1$@, depois lança: %2$@",
                         noChain: "Não tem papel próprio nas reações em cadeia: recebe tudo do jeito comum.",
                         stimuli: ["fogo", "água", "vento", "choque", "gelo", "luz", "som", "pimenta", "pancada", "ímã",
                                   "doce", "gosma", "hipnose", "cócegas"],
                         chainTitle: "Reações em cadeia",
                         chainHint: "Um joga o que segura no amigo mais próximo, que faz algo com isso e talvez jogue algo adiante. Cada reação vista fica guardada aqui.",
                         foundFormat: "%@ encontradas", raresTitle: "Eventos raros", unknownRare: "???",
                         rareGoldFormat: "+%@ de ouro", close: "Fechar", locked: "Bloqueado")
        case .de:
            return .init(search: "Nach Namen suchen", all: "Alle",
                         families: ["Stufenbelohnungen", "Wonder Boy", "Kuriositäten", "Tanz", "Spielzeug & Glück", "Party",
                                    "Absonderliches", "Werkstatt", "Jahrmarkt & Feld", "Das Labor", "Chaos"],
                         spots: ["Kopf", "Augen", "Hals", "Hand", "Rücken", "Füße"],
                         owned: "Im Besitz", notOwned: "Nicht im Besitz", sortTitle: "Sortieren nach",
                         sorts: ["Familie", "Seltenheit", "Name", "Preis"],
                         newBadge: "NEU", nothingMatches: "Nichts passt zu diesen Filtern.", clearFilters: "Filter zurücksetzen",
                         expandAll: "Alle öffnen", collapseAll: "Alle schließen", shownFormat: "%1$@ von %2$@",
                         dressing: "Einkleiden", wear: "Anziehen", worn: "Trägt es", levelReward: "Kommt mit einer Stufe",
                         inShop: "Gerade im Laden",
                         notInShop: "Gerade nicht im Laden; ein neues Sortiment kann es bringen.",
                         shopForOther: "Im Laden, aber der Laden kauft gerade für eine andere Figur. Ändere oben im Laden, für wen er kauft.",
                         throwsFormat: "Wirft: %@", reactsFormat: "Reagiert auf: %@",
                         reactsThrowsFormat: "Reagiert auf: %1$@, wirft dann: %2$@",
                         noChain: "Spielt bei Kettenreaktionen keine eigene Rolle: es nimmt sie ganz normal.",
                         stimuli: ["Feuer", "Wasser", "Wind", "Stromschlag", "Frost", "Licht", "Klang", "Pfeffer", "Stoß",
                                   "Magnet", "Süßes", "Schleim", "Hypnose", "Kitzeln"],
                         chainTitle: "Kettenreaktionen",
                         chainHint: "Einer wirft, was er hält, auf den nächsten Freund, der etwas daraus macht und vielleicht weiterwirft. Jede gesehene Reaktion wird hier festgehalten.",
                         foundFormat: "%@ gefunden", raresTitle: "Seltene Ereignisse", unknownRare: "???",
                         rareGoldFormat: "+%@ Gold", close: "Schließen", locked: "Gesperrt")
        case .fr:
            return .init(search: "Rechercher par nom", all: "Tout",
                         families: ["Récompenses de niveau", "Wonder Boy", "Curiosités", "Danse", "Jouets et chance", "Fête",
                                    "Bizarreries", "Atelier", "Foire et champs", "Le labo", "Chaos"],
                         spots: ["Tête", "Yeux", "Cou", "Main", "Dos", "Pieds"],
                         owned: "Possédé", notOwned: "Pas possédé", sortTitle: "Trier par",
                         sorts: ["Famille", "Rareté", "Nom", "Prix"],
                         newBadge: "NOUVEAU", nothingMatches: "Rien ne correspond à ces filtres.", clearFilters: "Effacer les filtres",
                         expandAll: "Tout ouvrir", collapseAll: "Tout fermer", shownFormat: "%1$@ sur %2$@",
                         dressing: "Habiller", wear: "Porter", worn: "Le porte", levelReward: "Vient avec un niveau",
                         inShop: "En boutique maintenant",
                         notInShop: "Pas en boutique maintenant ; un nouvel étalage peut l’apporter.",
                         shopForOther: "En boutique, mais la boutique achète pour une autre figure. Change pour qui elle achète dans la boutique ci-dessus.",
                         throwsFormat: "Lance : %@", reactsFormat: "Réagit à : %@",
                         reactsThrowsFormat: "Réagit à : %1$@, puis lance : %2$@",
                         noChain: "Ne joue aucun rôle à lui dans les réactions en chaîne : il les subit normalement.",
                         stimuli: ["feu", "eau", "vent", "décharge", "givre", "lumière", "son", "poivre", "coup", "aimant",
                                   "sucré", "bave", "hypnose", "chatouilles"],
                         chainTitle: "Réactions en chaîne",
                         chainHint: "L’un lance ce qu’il tient à l’ami le plus proche, qui en fait quelque chose et relance peut-être. Chaque réaction vue est gardée ici.",
                         foundFormat: "%@ trouvées", raresTitle: "Événements rares", unknownRare: "???",
                         rareGoldFormat: "+%@ d’or", close: "Fermer", locked: "Verrouillé")
        case .it:
            return .init(search: "Cerca per nome", all: "Tutto",
                         families: ["Premi di livello", "Wonder Boy", "Curiosità", "Danza", "Giocattoli e fortuna", "Festa",
                                    "Stranezze", "Bottega", "Fiera e campi", "Il laboratorio", "Caos"],
                         spots: ["Testa", "Occhi", "Collo", "Mano", "Schiena", "Piedi"],
                         owned: "Posseduti", notOwned: "Non posseduti", sortTitle: "Ordina per",
                         sorts: ["Famiglia", "Rarità", "Nome", "Prezzo"],
                         newBadge: "NUOVO", nothingMatches: "Niente corrisponde a questi filtri.", clearFilters: "Azzera filtri",
                         expandAll: "Apri tutto", collapseAll: "Chiudi tutto", shownFormat: "%1$@ di %2$@",
                         dressing: "Vesti", wear: "Indossa", worn: "Lo indossa", levelReward: "Arriva con un livello",
                         inShop: "Nel negozio ora",
                         notInShop: "Non è nel negozio ora; una nuova vetrina può portarlo.",
                         shopForOther: "È nel negozio, ma il negozio compra per un’altra figura. Cambia per chi compra nel negozio qui sopra.",
                         throwsFormat: "Lancia: %@", reactsFormat: "Reagisce a: %@",
                         reactsThrowsFormat: "Reagisce a: %1$@, poi lancia: %2$@",
                         noChain: "Non ha un ruolo suo nelle reazioni a catena: le subisce normalmente.",
                         stimuli: ["fuoco", "acqua", "vento", "scossa", "gelo", "luce", "suono", "pepe", "botta", "calamita",
                                   "dolce", "melma", "ipnosi", "solletico"],
                         chainTitle: "Reazioni a catena",
                         chainHint: "Uno lancia ciò che tiene all’amico più vicino, che ne fa qualcosa e magari rilancia. Ogni reazione vista resta qui.",
                         foundFormat: "%@ trovate", raresTitle: "Eventi rari", unknownRare: "???",
                         rareGoldFormat: "+%@ d’oro", close: "Chiudi", locked: "Bloccato")
        case .sk:
            return .init(search: "Hľadať podľa názvu", all: "Všetko",
                         families: ["Odmeny za úroveň", "Wonder Boy", "Kuriozity", "Tanec", "Hračky a šťastie", "Párty",
                                    "Čudesá", "Dielňa", "Jarmok a lúka", "Laboratórium", "Chaos"],
                         spots: ["Hlava", "Oči", "Krk", "Ruka", "Chrbát", "Nohy"],
                         owned: "Vlastní", notOwned: "Nevlastní", sortTitle: "Zoradiť podľa",
                         sorts: ["Rodina", "Vzácnosť", "Názov", "Cena"],
                         newBadge: "NOVÉ", nothingMatches: "Týmto filtrom nič nezodpovedá.", clearFilters: "Zrušiť filtre",
                         expandAll: "Otvoriť všetko", collapseAll: "Zavrieť všetko", shownFormat: "%1$@ z %2$@",
                         dressing: "Oblieka", wear: "Obliecť", worn: "Má to na sebe", levelReward: "Prichádza s úrovňou",
                         inShop: "Práve v obchode",
                         notInShop: "Teraz nie je v obchode; nová ponuka ho môže priniesť.",
                         shopForOther: "Je v obchode, ale obchod nakupuje pre inú postavičku. Zmeň, pre koho nakupuje, v obchode vyššie.",
                         throwsFormat: "Hádže: %@", reactsFormat: "Reaguje na: %@",
                         reactsThrowsFormat: "Reaguje na: %1$@, potom hádže: %2$@",
                         noChain: "V reťazových reakciách nehrá vlastnú rolu: berie ich obyčajne.",
                         stimuli: ["oheň", "voda", "vietor", "výboj", "mráz", "svetlo", "zvuk", "korenie", "úder", "magnet",
                                   "sladké", "sliz", "hypnóza", "šteklenie"],
                         chainTitle: "Reťazové reakcie",
                         chainHint: "Jeden hodí, čo drží, najbližšiemu kamarátovi, ten s tým niečo urobí a možno hodí ďalej. Každá videná reakcia sa uloží sem.",
                         foundFormat: "Nájdené: %@", raresTitle: "Vzácne udalosti", unknownRare: "???",
                         rareGoldFormat: "+%@ zlata", close: "Zavrieť", locked: "Zamknuté")
        case .uk:
            return .init(search: "Пошук за назвою", all: "Усе",
                         families: ["Нагороди за рівень", "Wonder Boy", "Дивовижі", "Танець", "Іграшки й удача", "Вечірка",
                                    "Дивацтва", "Майстерня", "Ярмарок і поле", "Лабораторія", "Хаос"],
                         spots: ["Голова", "Очі", "Шия", "Рука", "Спина", "Ноги"],
                         owned: "Є", notOwned: "Немає", sortTitle: "Сортування",
                         sorts: ["Родина", "Рідкісність", "Назва", "Ціна"],
                         newBadge: "НОВЕ", nothingMatches: "Нічого не підходить під ці фільтри.", clearFilters: "Скинути фільтри",
                         expandAll: "Відкрити все", collapseAll: "Закрити все", shownFormat: "%1$@ з %2$@",
                         dressing: "Одягаємо", wear: "Одягнути", worn: "Уже вдягнуто", levelReward: "Дається з рівнем",
                         inShop: "Зараз у крамниці",
                         notInShop: "Зараз немає в крамниці; новий асортимент може його принести.",
                         shopForOther: "Є в крамниці, але крамниця купує для іншої фігурки. Зміни, для кого вона купує, у крамниці вище.",
                         throwsFormat: "Кидає: %@", reactsFormat: "Реагує на: %@",
                         reactsThrowsFormat: "Реагує на: %1$@, потім кидає: %2$@",
                         noChain: "У ланцюгових реакціях не має своєї ролі: сприймає їх звичайно.",
                         stimuli: ["вогонь", "вода", "вітер", "розряд", "мороз", "світло", "звук", "перець", "удар", "магніт",
                                   "солодке", "слиз", "гіпноз", "лоскіт"],
                         chainTitle: "Ланцюгові реакції",
                         chainHint: "Один кидає те, що тримає, найближчому другові, а той щось із цим робить і, може, кидає далі. Кожна побачена реакція зберігається тут.",
                         foundFormat: "Знайдено: %@", raresTitle: "Рідкісні події", unknownRare: "???",
                         rareGoldFormat: "+%@ золота", close: "Закрити", locked: "Заблоковано")
        case .ru:
            return .init(search: "Поиск по названию", all: "Всё",
                         families: ["Награды за уровень", "Wonder Boy", "Диковинки", "Танец", "Игрушки и удача", "Вечеринка",
                                    "Странности", "Мастерская", "Ярмарка и поле", "Лаборатория", "Хаос"],
                         spots: ["Голова", "Глаза", "Шея", "Рука", "Спина", "Ноги"],
                         owned: "Есть", notOwned: "Нет", sortTitle: "Сортировка",
                         sorts: ["Семейство", "Редкость", "Название", "Цена"],
                         newBadge: "НОВОЕ", nothingMatches: "Под эти фильтры ничего не подходит.", clearFilters: "Сбросить фильтры",
                         expandAll: "Открыть все", collapseAll: "Закрыть все", shownFormat: "%1$@ из %2$@",
                         dressing: "Наряжаем", wear: "Надеть", worn: "Уже надето", levelReward: "Даётся за уровень",
                         inShop: "Сейчас в магазине",
                         notInShop: "Сейчас нет в магазине; новый ассортимент может его принести.",
                         shopForOther: "Есть в магазине, но магазин покупает для другой фигурки. Смени, для кого он покупает, в магазине выше.",
                         throwsFormat: "Бросает: %@", reactsFormat: "Реагирует на: %@",
                         reactsThrowsFormat: "Реагирует на: %1$@, затем бросает: %2$@",
                         noChain: "В цепных реакциях своей роли не играет: принимает их как обычно.",
                         stimuli: ["огонь", "вода", "ветер", "разряд", "мороз", "свет", "звук", "перец", "удар", "магнит",
                                   "сладкое", "слизь", "гипноз", "щекотка"],
                         chainTitle: "Цепные реакции",
                         chainHint: "Один бросает то, что держит, ближайшему другу, тот что-то с этим делает и, может, бросает дальше. Каждая увиденная реакция сохраняется здесь.",
                         foundFormat: "Найдено: %@", raresTitle: "Редкие события", unknownRare: "???",
                         rareGoldFormat: "+%@ золота", close: "Закрыть", locked: "Заблокировано")
        case .tr:
            return .init(search: "Ada göre ara", all: "Tümü",
                         families: ["Seviye ödülleri", "Wonder Boy", "Kuriozite", "Dans", "Oyuncak ve şans", "Parti",
                                    "Acayiplikler", "Atölye", "Panayır ve kır", "Laboratuvar", "Kaos"],
                         spots: ["Baş", "Gözler", "Boyun", "El", "Sırt", "Ayaklar"],
                         owned: "Sahip olunan", notOwned: "Sahip olunmayan", sortTitle: "Sırala",
                         sorts: ["Aile", "Nadirlik", "Ad", "Fiyat"],
                         newBadge: "YENİ", nothingMatches: "Bu filtrelere uyan bir şey yok.", clearFilters: "Filtreleri temizle",
                         expandAll: "Hepsini aç", collapseAll: "Hepsini kapat", shownFormat: "%2$@ içinde %1$@",
                         dressing: "Giydirilen", wear: "Giy", worn: "Üzerinde", levelReward: "Bir seviyeyle gelir",
                         inShop: "Şu an dükkânda",
                         notInShop: "Şu an dükkânda değil; yeni bir vitrin getirebilir.",
                         shopForOther: "Dükkânda, ama dükkân başka bir figür için alıyor. Yukarıdaki dükkânda kimin için aldığını değiştir.",
                         throwsFormat: "Fırlatır: %@", reactsFormat: "Tepki verir: %@",
                         reactsThrowsFormat: "Tepki verir: %1$@, sonra fırlatır: %2$@",
                         noChain: "Zincirleme tepkilerde kendine ait bir rolü yok: onları sıradan biçimde karşılar.",
                         stimuli: ["ateş", "su", "rüzgâr", "elektrik", "buz", "ışık", "ses", "biber", "darbe", "mıknatıs",
                                   "tatlı", "yapışkan", "hipnoz", "gıdıklama"],
                         chainTitle: "Zincirleme tepkiler",
                         chainHint: "Biri elindekini en yakın arkadaşına fırlatır; o da bununla bir şey yapar ve belki başka bir şey fırlatır. Görülen her tepki burada saklanır.",
                         foundFormat: "%@ bulundu", raresTitle: "Nadir olaylar", unknownRare: "???",
                         rareGoldFormat: "+%@ altın", close: "Kapat", locked: "Kilitli")
        case .ja:
            return .init(search: "名前で検索", all: "すべて",
                         families: ["レベル報酬", "Wonder Boy", "珍品", "ダンス", "おもちゃと運", "パーティー",
                                    "へんてこ", "工房", "縁日と野原", "ラボ", "カオス"],
                         spots: ["頭", "目", "首", "手", "背中", "足"],
                         owned: "所持", notOwned: "未所持", sortTitle: "並べ替え",
                         sorts: ["系統", "レア度", "名前", "価格"],
                         newBadge: "NEW", nothingMatches: "この条件に合うものはありません。", clearFilters: "条件をクリア",
                         expandAll: "すべて開く", collapseAll: "すべて閉じる", shownFormat: "%2$@件中%1$@件",
                         dressing: "着せる相手", wear: "着ける", worn: "着用中", levelReward: "レベルで手に入る",
                         inShop: "いまショップにあります",
                         notInShop: "いまはショップにありません。品ぞろえが変われば出るかもしれません。",
                         shopForOther: "ショップにありますが、いまは別のキャラ向けに売っています。上のショップで誰に買うかを変えてください。",
                         throwsFormat: "投げる：%@", reactsFormat: "反応する：%@",
                         reactsThrowsFormat: "反応する：%1$@ → 投げる：%2$@",
                         noChain: "連鎖反応では特別な役はありません。ふつうに受けます。",
                         stimuli: ["火", "水", "風", "電撃", "冷気", "光", "音", "コショウ", "衝撃", "磁力",
                                   "甘いもの", "ネバネバ", "催眠", "くすぐり"],
                         chainTitle: "連鎖反応",
                         chainHint: "手に持ったものをいちばん近い仲間に投げ、受けた仲間が何かして、さらに投げることも。見た反応はすべてここに記録されます。",
                         foundFormat: "発見 %@", raresTitle: "レアイベント", unknownRare: "???",
                         rareGoldFormat: "+%@ ゴールド", close: "閉じる", locked: "ロック中")
        case .ko:
            return .init(search: "이름으로 검색", all: "전체",
                         families: ["레벨 보상", "Wonder Boy", "진기한 물건", "댄스", "장난감과 행운", "파티",
                                    "괴짜 물건", "공방", "축제와 들판", "실험실", "대혼란"],
                         spots: ["머리", "눈", "목", "손", "등", "발"],
                         owned: "보유", notOwned: "미보유", sortTitle: "정렬",
                         sorts: ["계열", "희귀도", "이름", "가격"],
                         newBadge: "NEW", nothingMatches: "이 조건에 맞는 것이 없어요.", clearFilters: "필터 지우기",
                         expandAll: "모두 열기", collapseAll: "모두 닫기", shownFormat: "%2$@개 중 %1$@개",
                         dressing: "입힐 대상", wear: "착용", worn: "착용 중", levelReward: "레벨로 얻음",
                         inShop: "지금 상점에 있어요",
                         notInShop: "지금은 상점에 없어요. 진열이 바뀌면 나올 수 있어요.",
                         shopForOther: "상점에 있지만 지금은 다른 캐릭터를 위해 팔고 있어요. 위 상점에서 누구를 위해 살지 바꿔 주세요.",
                         throwsFormat: "던짐: %@", reactsFormat: "반응: %@",
                         reactsThrowsFormat: "반응: %1$@ → 던짐: %2$@",
                         noChain: "연쇄 반응에서 특별한 역할은 없어요. 평범하게 받아요.",
                         stimuli: ["불", "물", "바람", "전기", "냉기", "빛", "소리", "후추", "충격", "자력",
                                   "단것", "끈적이", "최면", "간지럼"],
                         chainTitle: "연쇄 반응",
                         chainHint: "손에 든 것을 가장 가까운 친구에게 던지면, 친구가 무언가를 하고 다시 던지기도 해요. 본 반응은 모두 여기에 기록돼요.",
                         foundFormat: "%@개 발견", raresTitle: "희귀 이벤트", unknownRare: "???",
                         rareGoldFormat: "+%@ 골드", close: "닫기", locked: "잠김")
        case .zhHans:
            return .init(search: "按名称搜索", all: "全部",
                         families: ["等级奖励", "Wonder Boy", "奇珍", "舞蹈", "玩具与好运", "派对",
                                    "怪东西", "工坊", "集市与田野", "实验室", "大混乱"],
                         spots: ["头", "眼", "颈", "手", "背", "脚"],
                         owned: "已拥有", notOwned: "未拥有", sortTitle: "排序",
                         sorts: ["系列", "稀有度", "名称", "价格"],
                         newBadge: "新", nothingMatches: "没有符合这些筛选条件的物品。", clearFilters: "清除筛选",
                         expandAll: "全部展开", collapseAll: "全部收起", shownFormat: "%1$@ / %2$@",
                         dressing: "装扮对象", wear: "穿戴", worn: "正在穿戴", levelReward: "随等级获得",
                         inShop: "商店里现在有",
                         notInShop: "商店里现在没有；换一批货可能会出现。",
                         shopForOther: "商店里有，但商店正在为另一个角色购买。请在上方商店中更改为谁购买。",
                         throwsFormat: "投出：%@", reactsFormat: "反应：%@",
                         reactsThrowsFormat: "反应：%1$@ → 投出：%2$@",
                         noChain: "在连锁反应中没有特别作用：按普通方式承受。",
                         stimuli: ["火", "水", "风", "电击", "冰霜", "光", "声音", "胡椒", "撞击", "磁力",
                                   "甜食", "黏液", "催眠", "挠痒"],
                         chainTitle: "连锁反应",
                         chainHint: "一个把手里的东西扔给最近的伙伴，伙伴做出反应，也许再扔下去。见过的每种反应都记录在这里。",
                         foundFormat: "已发现 %@", raresTitle: "稀有事件", unknownRare: "???",
                         rareGoldFormat: "+%@ 金币", close: "关闭", locked: "已锁定")
        case .zhHK, .zhTW:
            return .init(search: "依名稱搜尋", all: "全部",
                         families: ["等級獎勵", "Wonder Boy", "奇珍", "舞蹈", "玩具與好運", "派對",
                                    "怪東西", "工坊", "市集與田野", "實驗室", "大混亂"],
                         spots: ["頭", "眼", "頸", "手", "背", "腳"],
                         owned: "已擁有", notOwned: "未擁有", sortTitle: "排序",
                         sorts: ["系列", "稀有度", "名稱", "價格"],
                         newBadge: "新", nothingMatches: "沒有符合這些篩選條件的物品。", clearFilters: "清除篩選",
                         expandAll: "全部展開", collapseAll: "全部收合", shownFormat: "%1$@ / %2$@",
                         dressing: "裝扮對象", wear: "穿戴", worn: "正在穿戴", levelReward: "隨等級獲得",
                         inShop: "商店裡現在有",
                         notInShop: "商店裡現在沒有；換一批貨可能會出現。",
                         shopForOther: "商店裡有，但商店正在為另一個角色購買。請在上方商店中更改為誰購買。",
                         throwsFormat: "投出：%@", reactsFormat: "反應：%@",
                         reactsThrowsFormat: "反應：%1$@ → 投出：%2$@",
                         noChain: "在連鎖反應中沒有特別作用：以一般方式承受。",
                         stimuli: ["火", "水", "風", "電擊", "冰霜", "光", "聲音", "胡椒", "撞擊", "磁力",
                                   "甜食", "黏液", "催眠", "搔癢"],
                         chainTitle: "連鎖反應",
                         chainHint: "一個把手上的東西丟給最近的夥伴，夥伴做出反應，也許再丟下去。看過的每種反應都記錄在這裡。",
                         foundFormat: "已發現 %@", raresTitle: "稀有事件", unknownRare: "???",
                         rareGoldFormat: "+%@ 金幣", close: "關閉", locked: "已鎖定")
        }
    }
}
