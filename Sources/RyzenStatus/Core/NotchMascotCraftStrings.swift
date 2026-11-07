// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The workshop: the names of its eight things and a line on what each
/// does, in the order of `NotchMascotAccessory.craftItems`, and the words
/// of a shop that sells to one companion or another.
struct NotchMascotCraftStrings {
    let items: [String]
    let gags: [String]
    /// "For" a companion, before the picker of who the shop buys for.
    let forWhom: String
    /// A thing the chosen companion already has.
    let alreadyHas: String
    /// Over a companion as it shows off what was just bought for it.
    let newThing: String

    static let itemCount = 8

    func name(of accessory: NotchMascotAccessory) -> String? {
        NotchMascotAccessory.craftItems.firstIndex(of: accessory).map { items[$0] }
    }

    func gag(of accessory: NotchMascotAccessory) -> String? {
        NotchMascotAccessory.craftItems.firstIndex(of: accessory).map { gags[$0] }
    }

    var isComplete: Bool {
        items.count == Self.itemCount && gags.count == Self.itemCount
            && items.allSatisfy { !$0.isEmpty } && gags.allSatisfy { !$0.isEmpty }
            && !forWhom.isEmpty && !alreadyHas.isEmpty && !newThing.isEmpty
    }
}

extension FeatureStrings {
    // swiftlint:disable:next function_body_length
    static func notchMascotCraft(_ language: AppLanguage) -> NotchMascotCraftStrings {
        switch language {
        case .enUS:
            return .init(items: ["Electric Guitar", "Karate Belt", "Painter's Beret", "Matcha Bowl", "Boxing Gloves",
                                 "Telescope", "Shovel", "Pogo Stick"],
                         gags: ["A solo, sparks off the strings.", "A kata, a shout, a bow.", "Paints what it sees… on the floor.",
                                "Whisk, sip, deep breath.", "Shadow boxing, then the knockout pose.",
                                "Finds a star, even by day.", "Digs. Sometimes there is treasure.", "Boing, boing, boing… boing."],
                         forWhom: "For", alreadyHas: "Already has it", newThing: "New!")
        case .es:
            return .init(items: ["Guitarra eléctrica", "Cinta de karate", "Boina de pintor", "Cuenco de matcha", "Guantes de boxeo",
                                 "Telescopio", "Pala", "Saltarín"],
                         gags: ["Un solo, chispas en las cuerdas.", "Una kata, un grito, una reverencia.",
                                "Pinta lo que ve… en el suelo.", "Batir, sorber, respirar hondo.",
                                "Sombra de boxeo y pose de nocaut.", "Encuentra una estrella, hasta de día.",
                                "Cava. A veces hay tesoro.", "Boing, boing, boing… boing."],
                         forWhom: "Para", alreadyHas: "Ya lo tiene", newThing: "¡Nuevo!")
        case .ptBR:
            return .init(items: ["Guitarra elétrica", "Faixa de karatê", "Boina de pintor", "Tigela de matcha", "Luvas de boxe",
                                 "Telescópio", "Pá", "Pula-pula"],
                         gags: ["Um solo, faíscas nas cordas.", "Um kata, um grito, uma reverência.",
                                "Pinta o que vê… no chão.", "Bater, sorver, respirar fundo.",
                                "Boxe de sombra e pose de nocaute.", "Acha uma estrela, até de dia.",
                                "Cava. Às vezes há tesouro.", "Boing, boing, boing… boing."],
                         forWhom: "Para", alreadyHas: "Já tem", newThing: "Novo!")
        case .de:
            return .init(items: ["E-Gitarre", "Karategürtel", "Malerbarett", "Matcha-Schale", "Boxhandschuhe",
                                 "Teleskop", "Schaufel", "Pogo-Stab"],
                         gags: ["Ein Solo, Funken von den Saiten.", "Eine Kata, ein Schrei, eine Verbeugung.",
                                "Malt, was es sieht… auf den Boden.", "Schlagen, schlürfen, tief durchatmen.",
                                "Schattenboxen, dann die K.-o.-Pose.", "Findet einen Stern, sogar am Tag.",
                                "Gräbt. Manchmal liegt da ein Schatz.", "Boing, boing, boing… boing."],
                         forWhom: "Für", alreadyHas: "Hat es schon", newThing: "Neu!")
        case .fr:
            return .init(items: ["Guitare électrique", "Ceinture de karaté", "Béret de peintre", "Bol de matcha", "Gants de boxe",
                                 "Télescope", "Pelle", "Bâton sauteur"],
                         gags: ["Un solo, des étincelles sur les cordes.", "Un kata, un cri, un salut.",
                                "Peint ce qu’il voit… par terre.", "Fouetter, siroter, respirer à fond.",
                                "Boxe dans le vide, puis pose de K.-O.", "Trouve une étoile, même en plein jour.",
                                "Creuse. Parfois il y a un trésor.", "Boing, boing, boing… boing."],
                         forWhom: "Pour", alreadyHas: "L’a déjà", newThing: "Nouveau !")
        case .it:
            return .init(items: ["Chitarra elettrica", "Cintura di karate", "Basco da pittore", "Ciotola di matcha", "Guantoni da boxe",
                                 "Telescopio", "Pala", "Pogo stick"],
                         gags: ["Un assolo, scintille dalle corde.", "Un kata, un grido, un inchino.",
                                "Dipinge quello che vede… sul pavimento.", "Frustare, sorseggiare, respirare a fondo.",
                                "Boxe con l’ombra, poi posa da KO.", "Trova una stella, anche di giorno.",
                                "Scava. A volte c’è un tesoro.", "Boing, boing, boing… boing."],
                         forWhom: "Per", alreadyHas: "Ce l’ha già", newThing: "Nuovo!")
        case .sk:
            return .init(items: ["Elektrická gitara", "Karate opasok", "Maliarska baretka", "Miska matcha", "Boxerské rukavice",
                                 "Ďalekohľad", "Lopata", "Skákacia tyč"],
                         gags: ["Sólo, iskry zo strún.", "Kata, výkrik, úklon.", "Maľuje, čo vidí… na podlahu.",
                                "Šľahať, usrknúť, zhlboka dýchať.", "Box s tieňom a póza po knokaute.",
                                "Nájde hviezdu aj cez deň.", "Kope. Niekedy je tam poklad.", "Boing, boing, boing… boing."],
                         forWhom: "Pre", alreadyHas: "Už to má", newThing: "Nové!")
        case .uk:
            return .init(items: ["Електрогітара", "Пояс карате", "Берет художника", "Чаша матча", "Боксерські рукавиці",
                                 "Телескоп", "Лопата", "Пого-стік"],
                         gags: ["Соло, іскри зі струн.", "Ката, вигук, уклін.", "Малює, що бачить… на підлозі.",
                                "Збити, сьорбнути, глибоко вдихнути.", "Бій з тінню і поза нокауту.",
                                "Знаходить зірку навіть удень.", "Копає. Іноді там скарб.", "Боінг, боінг, боінг… боінг."],
                         forWhom: "Для", alreadyHas: "Уже має", newThing: "Нове!")
        case .ru:
            return .init(items: ["Электрогитара", "Пояс карате", "Берет художника", "Чаша матча", "Боксёрские перчатки",
                                 "Телескоп", "Лопата", "Пого-стик"],
                         gags: ["Соло, искры со струн.", "Ката, крик, поклон.", "Рисует, что видит… на полу.",
                                "Взбить, отхлебнуть, глубоко вдохнуть.", "Бой с тенью и поза нокаута.",
                                "Находит звезду даже днём.", "Копает. Иногда там клад.", "Боинг, боинг, боинг… боинг."],
                         forWhom: "Для", alreadyHas: "Уже есть", newThing: "Новое!")
        case .tr:
            return .init(items: ["Elektro gitar", "Karate kuşağı", "Ressam beresi", "Matcha kâsesi", "Boks eldivenleri",
                                 "Teleskop", "Kürek", "Zıplama çubuğu"],
                         gags: ["Bir solo, tellerden kıvılcımlar.", "Bir kata, bir nara, bir selam.",
                                "Gördüğünü çizer… yere.", "Çırp, yudumla, derin nefes al.",
                                "Gölge boksu, sonra nakavt pozu.", "Gündüz bile bir yıldız bulur.",
                                "Kazar. Bazen hazine çıkar.", "Boing, boing, boing… boing."],
                         forWhom: "Kime", alreadyHas: "Zaten var", newThing: "Yeni!")
        case .ja:
            return .init(items: ["エレキギター", "空手の帯", "画家のベレー帽", "抹茶碗", "ボクシンググローブ",
                                 "望遠鏡", "シャベル", "ホッピング"],
                         gags: ["ソロ演奏、弦から火花。", "型、気合い、礼。", "見たものを描く…床に。",
                                "点てて、すすって、深呼吸。", "シャドーボクシングからKOポーズ。",
                                "昼でも星を見つける。", "掘る。たまに宝が出る。", "ボイン、ボイン、ボイン…ボイン。"],
                         forWhom: "贈る相手", alreadyHas: "もう持っている", newThing: "新入荷！")
        case .ko:
            return .init(items: ["일렉 기타", "가라테 띠", "화가 베레모", "말차 그릇", "복싱 글러브",
                                 "망원경", "삽", "포고 스틱"],
                         gags: ["솔로 연주, 줄에서 튀는 불꽃.", "품새, 기합, 인사.", "보이는 걸 그린다… 바닥에.",
                                "젓고, 홀짝이고, 깊게 숨쉬기.", "섀도복싱 뒤 KO 포즈.",
                                "낮에도 별을 찾아낸다.", "판다. 가끔 보물이 나온다.", "통, 통, 통… 통."],
                         forWhom: "받는 친구", alreadyHas: "이미 있음", newThing: "새 물건!")
        case .zhHans:
            return .init(items: ["电吉他", "空手道腰带", "画家贝雷帽", "抹茶碗", "拳击手套",
                                 "望远镜", "铲子", "弹跳杆"],
                         gags: ["一段独奏，琴弦迸火花。", "一套型、一声喝、一个礼。", "把看到的画下来……画在地上。",
                                "打发、啜饮、深呼吸。", "打完空拳摆出击倒姿势。",
                                "白天也能找到星星。", "挖啊挖。有时挖到宝。", "蹦、蹦、蹦……蹦。"],
                         forWhom: "送给", alreadyHas: "已经有了", newThing: "新货！")
        case .zhHK, .zhTW:
            return .init(items: ["電吉他", "空手道腰帶", "畫家貝雷帽", "抹茶碗", "拳擊手套",
                                 "望遠鏡", "鏟子", "彈跳桿"],
                         gags: ["一段獨奏，琴弦迸火花。", "一套型、一聲喝、一個禮。", "把看到的畫下來……畫在地上。",
                                "打發、啜飲、深呼吸。", "打完空拳擺出擊倒姿勢。",
                                "白天也能找到星星。", "挖啊挖。有時挖到寶。", "蹦、蹦、蹦……蹦。"],
                         forWhom: "送給", alreadyHas: "已經有了", newThing: "新貨！")
        }
    }
}
