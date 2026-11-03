// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The party gear: the names and a line on what each does, in the order of
/// `NotchMascotAccessory.partyItems`.
struct NotchMascotPartyStrings {
    let items: [String]
    let gags: [String]

    static let itemCount = 16

    func name(of accessory: NotchMascotAccessory) -> String? {
        NotchMascotAccessory.partyItems.firstIndex(of: accessory).map { items[$0] }
    }

    func gag(of accessory: NotchMascotAccessory) -> String? {
        NotchMascotAccessory.partyItems.firstIndex(of: accessory).map { gags[$0] }
    }

    var isComplete: Bool {
        items.count == Self.itemCount && gags.count == Self.itemCount
            && items.allSatisfy { !$0.isEmpty } && gags.allSatisfy { !$0.isEmpty }
    }
}

extension FeatureStrings {
    // swiftlint:disable:next function_body_length
    static func notchMascotParty(_ language: AppLanguage) -> NotchMascotPartyStrings {
        switch language {
        case .enUS:
            return .init(items: ["Snare Drum", "Microphone", "Maracas", "Soccer Ball", "Kite", "Pillow", "Marshmallow Stick",
                                 "Water Pistol", "Confetti Cannon", "Paper Plane", "Megaphone", "Whistle", "Hula Hoop",
                                 "Juggling Balls", "Walkie-Talkie", "Picnic Basket"],
                         gags: ["A drum solo, and a rimshot.", "Karaoke time: one more song!", "Shake, shake, cha-cha.",
                                "Keepy-uppy: how many can it do?", "Up it goes on its string.", "Fluffed, then a nap.",
                                "Roasted golden over the fire.", "Squirt! Nobody stays dry.", "Boom: confetti everywhere.",
                                "Thrown far, and back it glides.", "Speaks up. A lot.", "Fweet! Yellow card.",
                                "Round and round until dizzy.", "Three balls, never one dropped.", "Over. Do you copy?",
                                "A cloth, a snack, a sunny spot."])
        case .es:
            return .init(items: ["Tambor", "Micrófono", "Maracas", "Pelota de fútbol", "Barrilete", "Almohada",
                                 "Malvavisco en palito", "Pistola de agua", "Cañón de confeti", "Avión de papel", "Megáfono",
                                 "Silbato", "Aro de hula hula", "Pelotas de malabares", "Walkie-talkie", "Canasta de pícnic"],
                         gags: ["Un solo de batería, y platillo.", "Karaoke: ¡otra canción!", "Chiqui, chiqui, cha-cha.",
                                "Jueguito: ¿cuántas hace sin que caiga?", "Sube y sube con su hilo.", "La mullís y a dormir.",
                                "Dorado al fuego.", "¡Chorro! Nadie queda seco.", "¡Bum! Confeti por todos lados.",
                                "Se lanza lejos y vuelve planeando.", "Habla fuerte. Muy fuerte.", "¡Priiit! Tarjeta amarilla.",
                                "Vueltas y vueltas hasta marearse.", "Tres pelotas y ninguna al piso.", "Cambio. ¿Me copiás?",
                                "Un mantel, algo rico y un rincón al sol."])
        case .ptBR:
            return .init(items: ["Tambor", "Microfone", "Maracas", "Bola de futebol", "Pipa", "Travesseiro",
                                 "Marshmallow no palito", "Pistola de água", "Canhão de confete", "Avião de papel", "Megafone",
                                 "Apito", "Bambolê", "Bolinhas de malabares", "Walkie-talkie", "Cesta de piquenique"],
                         gags: ["Um solo de bateria, e prato.", "Karaokê: mais uma!", "Chique, chique, chá-chá.",
                                "Embaixadinhas: quantas consegue?", "Sobe e sobe na linha.", "Afofado, e uma soneca.",
                                "Tostado dourado no fogo.", "Esguicho! Ninguém fica seco.", "Bum: confete por todo lado.",
                                "Vai longe e volta planando.", "Fala alto. Muito alto.", "Priii! Cartão amarelo.",
                                "Gira e gira até ficar tonto.", "Três bolinhas, nenhuma no chão.", "Câmbio. Na escuta?",
                                "Uma toalha, um lanche, um cantinho ao sol."])
        case .de:
            return .init(items: ["Snaredrum", "Mikrofon", "Maracas", "Fußball", "Drachen", "Kissen", "Marshmallow-Spieß",
                                 "Wasserpistole", "Konfettikanone", "Papierflieger", "Megafon", "Pfeife", "Hula-Hoop-Reifen",
                                 "Jonglierbälle", "Walkie-Talkie", "Picknickkorb"],
                         gags: ["Ein Trommelsolo mit Tusch.", "Karaoke: noch ein Lied!", "Schüttel, schüttel, Cha-Cha.",
                                "Hochhalten: wie oft schafft es das?", "Er steigt an seiner Schnur.", "Aufgeschüttelt, dann ein Nickerchen.",
                                "Goldbraun über dem Feuer.", "Spritz! Keiner bleibt trocken.", "Bumm: überall Konfetti.",
                                "Weit geworfen, und er gleitet zurück.", "Spricht laut. Sehr laut.", "Pfiff! Gelbe Karte.",
                                "Rundherum, bis ihm schwindlig wird.", "Drei Bälle, keiner fällt.", "Over. Hörst du mich?",
                                "Eine Decke, ein Snack, ein Platz an der Sonne."])
        case .fr:
            return .init(items: ["Caisse claire", "Micro", "Maracas", "Ballon de foot", "Cerf-volant", "Oreiller",
                                 "Guimauve sur bâton", "Pistolet à eau", "Canon à confettis", "Avion en papier", "Mégaphone",
                                 "Sifflet", "Cerceau", "Balles de jonglage", "Talkie-walkie", "Panier de pique-nique"],
                         gags: ["Un solo de batterie, et cymbale.", "Karaoké : encore une !", "Ça secoue, cha-cha.",
                                "Jongles au pied : combien d’affilée ?", "Il monte au bout de son fil.", "Bien tapé, puis une sieste.",
                                "Doré au-dessus du feu.", "Pschitt ! Personne ne reste sec.", "Boum : des confettis partout.",
                                "Lancé au loin, il revient en planant.", "Il parle fort. Très fort.", "Priiit ! Carton jaune.",
                                "Ça tourne jusqu’au tournis.", "Trois balles, aucune ne tombe.", "À vous. Vous me recevez ?",
                                "Une nappe, un en-cas, un coin de soleil."])
        case .it:
            return .init(items: ["Rullante", "Microfono", "Maracas", "Pallone", "Aquilone", "Cuscino", "Marshmallow allo spiedo",
                                 "Pistola ad acqua", "Cannone di coriandoli", "Aeroplanino di carta", "Megafono", "Fischietto",
                                 "Hula hoop", "Palline da giocoliere", "Walkie-talkie", "Cestino da picnic"],
                         gags: ["Un assolo di batteria, e piatto.", "Karaoke: ancora una!", "Scuoti, scuoti, cha-cha.",
                                "Palleggi: quanti di fila?", "Sale e sale col suo filo.", "Sprimacciato, poi un pisolino.",
                                "Dorato sul fuoco.", "Spruzzo! Nessuno resta asciutto.", "Bum: coriandoli ovunque.",
                                "Lanciato lontano, torna planando.", "Parla forte. Molto forte.", "Fiii! Cartellino giallo.",
                                "Gira e gira fino a girare la testa.", "Tre palline, nessuna cade.", "Passo. Mi ricevi?",
                                "Una tovaglia, uno spuntino, un angolo al sole."])
        case .sk:
            return .init(items: ["Malý bubon", "Mikrofón", "Maracas", "Futbalová lopta", "Šarkan", "Vankúš", "Marshmallow na paličke",
                                 "Vodná pištoľ", "Konfetové delo", "Papierové lietadlo", "Megafón", "Píšťalka", "Hula hop",
                                 "Žonglovacie loptičky", "Vysielačka", "Piknikový košík"],
                         gags: ["Bubnové sólo a činel.", "Karaoke: ešte jednu!", "Šuch, šuch, ča-ča.",
                                "Žonglovanie: koľkokrát to dá?", "Stúpa na svojej šnúre.", "Načechrať a šlofík.",
                                "Opečený dozlatista nad ohňom.", "Strek! Nikto neostane suchý.", "Bum: konfety všade.",
                                "Hodené ďaleko, priletí späť.", "Hovorí nahlas. Veľmi nahlas.", "Píí! Žltá karta.",
                                "Dookola, až sa mu zatočí hlava.", "Tri loptičky, ani jedna nespadne.", "Prepínam. Počuješ ma?",
                                "Deka, desiata a miesto na slnku."])
        case .uk:
            return .init(items: ["Малий барабан", "Мікрофон", "Маракаси", "Футбольний м’яч", "Повітряний змій", "Подушка",
                                 "Маршмелоу на паличці", "Водяний пістолет", "Конфетна гармата", "Паперовий літачок", "Мегафон",
                                 "Свисток", "Обруч", "М’ячі для жонглювання", "Рація", "Кошик для пікніка"],
                         gags: ["Соло на барабані — і тарілка.", "Караоке: ще одну!", "Шур-шур, ча-ча.",
                                "Набивання: скільки разів поспіль?", "Злітає вгору на мотузці.", "Збити — і подрімати.",
                                "Підрум’янений над вогнем.", "Пш-ш! Сухим не лишиться ніхто.", "Бум: конфеті скрізь.",
                                "Летить далеко й повертається.", "Говорить голосно. Дуже.", "Фі-і-іть! Жовта картка.",
                                "Кружляє, аж голова йде обертом.", "Три м’ячі, жоден не падає.", "Прийом. Як чуєте?",
                                "Скатертина, перекус і місце на сонці."])
        case .ru:
            return .init(items: ["Малый барабан", "Микрофон", "Маракасы", "Футбольный мяч", "Воздушный змей", "Подушка",
                                 "Маршмеллоу на палочке", "Водяной пистолет", "Конфетти-пушка", "Бумажный самолётик", "Мегафон",
                                 "Свисток", "Обруч", "Мячи для жонглирования", "Рация", "Корзина для пикника"],
                         gags: ["Соло на барабане — и тарелка.", "Караоке: ещё одну!", "Шух-шух, ча-ча.",
                                "Чеканка: сколько раз подряд?", "Взлетает ввысь на верёвочке.", "Взбить — и вздремнуть.",
                                "Подрумяненный над огнём.", "Пш-ш! Сухим не останется никто.", "Бум: конфетти повсюду.",
                                "Летит далеко и возвращается.", "Говорит громко. Очень.", "Фью-ить! Жёлтая карточка.",
                                "Кружится, пока не закружится голова.", "Три мяча, ни один не падает.", "Приём. Как слышно?",
                                "Скатерть, перекус и место на солнце."])
        case .tr:
            return .init(items: ["Trampet", "Mikrofon", "Marakas", "Futbol topu", "Uçurtma", "Yastık", "Çubukta marshmallow",
                                 "Su tabancası", "Konfeti topu", "Kâğıt uçak", "Megafon", "Düdük", "Hula hoop",
                                 "Jonglör topları", "Telsiz", "Piknik sepeti"],
                         gags: ["Bir davul solosu ve zil.", "Karaoke: bir şarkı daha!", "Salla salla, ça-ça.",
                                "Top sektirme: kaç tane yapacak?", "İpiyle yükseldikçe yükselir.", "Kabartılır, sonra şekerleme.",
                                "Ateşte altın gibi kızarır.", "Fış! Kimse kuru kalmaz.", "Bum: her yer konfeti.",
                                "Uzağa atılır, süzülüp geri gelir.", "Yüksek sesle konuşur. Çok.", "Düüt! Sarı kart.",
                                "Başı dönene kadar döner.", "Üç top, hiçbiri düşmez.", "Tamam. Beni duyuyor musun?",
                                "Bir örtü, bir atıştırmalık, güneşli bir köşe."])
        case .ja:
            return .init(items: ["スネアドラム", "マイク", "マラカス", "サッカーボール", "たこ", "まくら", "マシュマロの串",
                                 "水鉄砲", "紙吹雪キャノン", "紙飛行機", "メガホン", "ホイッスル", "フラフープ",
                                 "ジャグリングボール", "トランシーバー", "ピクニックバスケット"],
                         gags: ["ドラムソロでジャーン。", "カラオケ：もう一曲！", "シャカシャカ、チャチャ。",
                                "リフティング：何回できる？", "糸に乗って高く上がる。", "ふかふかにしてお昼寝。",
                                "火でこんがりきつね色。", "ピュッ！ 誰もぬれずにいられない。", "ドーン：紙吹雪だらけ。",
                                "遠くへ飛んで、すーっと戻る。", "大声で話す。とても大声で。", "ピーッ！ イエローカード。",
                                "目が回るまでくるくる。", "三つのボール、一つも落とさない。", "どうぞ。聞こえますか？",
                                "シートとおやつと日なたの場所。"])
        case .ko:
            return .init(items: ["스네어 드럼", "마이크", "마라카스", "축구공", "연", "베개", "마시멜로 꼬치",
                                 "물총", "컨페티 대포", "종이비행기", "메가폰", "호루라기", "훌라후프",
                                 "저글링 공", "무전기", "피크닉 바구니"],
                         gags: ["드럼 솔로, 그리고 심벌.", "노래방: 한 곡 더!", "찰찰, 차차.",
                                "리프팅: 몇 번이나 할까?", "실을 타고 높이 올라가요.", "폭신하게 털고 낮잠.",
                                "불에 노릇노릇 구워요.", "찍! 아무도 안 젖을 수 없어요.", "펑: 사방에 꽃가루.",
                                "멀리 날아갔다가 돌아와요.", "크게 말해요. 아주 크게.", "삐익! 옐로카드.",
                                "어지러울 때까지 빙글빙글.", "공 세 개, 하나도 안 떨어뜨려요.", "오버. 들리나요?",
                                "돗자리, 간식, 햇볕 드는 자리."])
        case .zhHans:
            return .init(items: ["小军鼓", "麦克风", "沙锤", "足球", "风筝", "枕头", "棉花糖签",
                                 "水枪", "彩带炮", "纸飞机", "扩音器", "哨子", "呼啦圈",
                                 "杂耍球", "对讲机", "野餐篮"],
                         gags: ["来段鼓独奏，再一声镲。", "卡拉OK：再来一首！", "沙沙沙，恰恰恰。",
                                "颠球：能颠几个？", "顺着线越飞越高。", "拍松了，睡个午觉。",
                                "在火上烤得金黄。", "滋！谁也别想不湿。", "砰：到处都是彩带。",
                                "扔得老远，又滑翔回来。", "大声说话，非常大声。", "嘟！黄牌警告。",
                                "转啊转，转到头晕。", "三个球，一个也不掉。", "完毕。收到请回答？",
                                "一块布、一点零食、一片阳光。"])
        case .zhTW:
            return .init(items: ["小鼓", "麥克風", "沙鈴", "足球", "風箏", "枕頭", "棉花糖串",
                                 "水槍", "彩帶砲", "紙飛機", "擴音器", "哨子", "呼拉圈",
                                 "雜耍球", "對講機", "野餐籃"],
                         gags: ["來段鼓獨奏，再一聲鈸。", "KTV：再來一首！", "沙沙沙，恰恰恰。",
                                "挑球：能挑幾下？", "順著線越飛越高。", "拍鬆了，睡個午覺。",
                                "在火上烤得金黃。", "滋！誰也別想不濕。", "砰：到處都是彩帶。",
                                "丟得老遠，又滑翔回來。", "大聲說話，非常大聲。", "嗶！黃牌警告。",
                                "轉啊轉，轉到頭暈。", "三顆球，一顆也不掉。", "完畢。收到請回答？",
                                "一塊布、一點點心、一片陽光。"])
        case .zhHK:
            return .init(items: ["小鼓", "咪", "沙槌", "足球", "風箏", "枕頭", "棉花糖串",
                                 "水槍", "彩帶炮", "紙飛機", "大聲公", "銀雞", "呼拉圈",
                                 "雜耍波", "對講機", "野餐籃"],
                         gags: ["嚟段鼓獨奏，再一下鑔。", "K歌：再唱多首！", "沙沙沙，恰恰恰。",
                                "踢波仔：可以踢幾多下？", "跟住條線越飛越高。", "拍鬆咗，瞓個晏覺。",
                                "喺火上面燒到金黃。", "滋！冇人可以唔濕。", "砰：周圍都係彩帶。",
                                "掟到好遠，又滑翔返嚟。", "大大聲講嘢，好大聲。", "嗶！黃牌。",
                                "轉吓轉，轉到頭暈。", "三個波，一個都唔跌。", "完畢。收唔收到？",
                                "一張布、少少小食、一片陽光。"])
        }
    }
}
