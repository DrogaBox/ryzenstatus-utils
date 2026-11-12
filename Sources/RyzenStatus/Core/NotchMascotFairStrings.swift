// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The fair and the field: the names of its twenty-four things and a line
/// on what each does, in the order of `NotchMascotAccessory.fairItems`.
struct NotchMascotFairStrings {
    let items: [String]
    let gags: [String]

    static let itemCount = 24

    func name(of accessory: NotchMascotAccessory) -> String? {
        NotchMascotAccessory.fairItems.firstIndex(of: accessory).map { items[$0] }
    }

    func gag(of accessory: NotchMascotAccessory) -> String? {
        NotchMascotAccessory.fairItems.firstIndex(of: accessory).map { gags[$0] }
    }

    var isComplete: Bool {
        items.count == Self.itemCount && gags.count == Self.itemCount
            && items.allSatisfy { !$0.isEmpty } && gags.allSatisfy { !$0.isEmpty }
    }
}

extension FeatureStrings {
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    static func notchMascotFair(_ language: AppLanguage) -> NotchMascotFairStrings {
        switch language {
        case .enUS:
            return .init(items: ["Fishing Rod", "Butterfly Net", "Watering Can", "Potted Cactus", "Frying Pan", "Cupcake",
                                 "Lollipop", "Trumpet", "Violin", "Basketball", "Puzzle Cube", "Answer Ball", "Pinwheel",
                                 "Slingshot", "Balloon Dog", "Sparkler", "Boombox", "Hard Hat", "Astronaut Helmet",
                                 "Graduation Cap", "Flower Crown", "Binoculars", "Super Cape", "Stilts"],
                         gags: ["Casts, waits… a fish, or an old boot.", "Chases a butterfly, catches it, lets it go.",
                                "Waters the floor until a flower comes up.", "Gives it a hug. Ouch.",
                                "Flips a pancake. Usually catches it.", "A candle, a wish, a single bite.",
                                "One lick, then a sugar rush.", "Ta-daa! For no reason at all.",
                                "The saddest song, with real tears.", "Dribble, dunk, swish. Or clank.",
                                "Twists and twists… solved, or not.", "Shake it and ask. It answers.",
                                "Runs into the wind to make it spin.", "Aims at nothing, hits something.",
                                "Squeak, squeak, a dog… pop.", "Writes its name in sparks.",
                                "Drops the beat and breakdances.", "Builds a tower. It falls.",
                                "One small step, very slowly.", "Throws its cap to the sky.",
                                "Spring follows it around.", "Spots a bird far, far away.",
                                "Up, up… and a pose.", "Taller than everyone, for a moment."])
        case .es:
            return .init(items: ["Caña de pescar", "Red de mariposas", "Regadera", "Cactus en maceta", "Sartén", "Cupcake",
                                 "Piruleta", "Trompeta", "Violín", "Pelota de baloncesto", "Cubo de colores", "Bola adivina",
                                 "Molinillo", "Tirachinas", "Perro de globo", "Bengala", "Radiocasete", "Casco de obra",
                                 "Casco de astronauta", "Birrete", "Corona de flores", "Prismáticos", "Supercapa", "Zancos"],
                         gags: ["Lanza, espera… un pez, o una bota vieja.", "Persigue una mariposa, la atrapa y la suelta.",
                                "Riega el suelo hasta que sale una flor.", "Le da un abrazo. Ay.",
                                "Voltea una tortita. Casi siempre la atrapa.", "Una vela, un deseo, un solo bocado.",
                                "Un lametón y subidón de azúcar.", "¡Tachán! Porque sí.",
                                "La canción más triste, con lágrimas de verdad.", "Bote, mate, ¡zas! O ¡clanc!",
                                "Gira y gira… resuelto, o no.", "Agítala y pregunta. Responde.",
                                "Corre contra el viento para hacerlo girar.", "Apunta a nada y le da a algo.",
                                "Ñic, ñic, un perro… ¡pum!", "Escribe su nombre con chispas.",
                                "Suelta el ritmo y hace breakdance.", "Construye una torre. Se cae.",
                                "Un pequeño paso, muy despacio.", "Lanza el birrete al cielo.",
                                "La primavera lo sigue a todas partes.", "Ve un pájaro muy, muy lejos.",
                                "Arriba, arriba… y pose.", "Más alto que nadie, un momento."])
        case .ptBR:
            return .init(items: ["Vara de pescar", "Rede de borboletas", "Regador", "Cacto no vaso", "Frigideira", "Cupcake",
                                 "Pirulito", "Trompete", "Violino", "Bola de basquete", "Cubo de cores", "Bola das respostas",
                                 "Cata-vento", "Estilingue", "Cachorro de balão", "Estrelinha", "Rádio portátil",
                                 "Capacete de obra", "Capacete de astronauta", "Capelo", "Coroa de flores", "Binóculos",
                                 "Supercapa", "Pernas de pau"],
                         gags: ["Lança, espera… um peixe, ou uma bota velha.", "Persegue uma borboleta, pega e solta.",
                                "Rega o chão até nascer uma flor.", "Dá um abraço. Ai.",
                                "Vira uma panqueca. Quase sempre pega.", "Uma vela, um desejo, uma mordida só.",
                                "Uma lambida e muita energia.", "Tchã-rã! Sem motivo nenhum.",
                                "A música mais triste, com lágrimas de verdade.", "Quica, enterra, chuá. Ou clanc.",
                                "Gira e gira… resolvido, ou não.", "Sacuda e pergunte. Ela responde.",
                                "Corre contra o vento para girar.", "Mira no nada, acerta alguma coisa.",
                                "Nhec, nhec, um cachorro… pof.", "Escreve o nome com faíscas.",
                                "Solta a batida e dança break.", "Monta uma torre. Ela cai.",
                                "Um pequeno passo, bem devagar.", "Joga o capelo para o céu.",
                                "A primavera vai atrás dele.", "Avista um pássaro bem longe.",
                                "Para o alto… e uma pose.", "Mais alto que todos, por um instante."])
        case .de:
            return .init(items: ["Angelrute", "Schmetterlingsnetz", "Gießkanne", "Topfkaktus", "Bratpfanne", "Cupcake",
                                 "Lutscher", "Trompete", "Geige", "Basketball", "Farbwürfel", "Orakelkugel", "Windrad",
                                 "Steinschleuder", "Ballonhund", "Wunderkerze", "Kassettenrekorder", "Bauhelm",
                                 "Astronautenhelm", "Absolventenhut", "Blumenkranz", "Fernglas", "Supercape", "Stelzen"],
                         gags: ["Auswerfen, warten… ein Fisch oder ein alter Stiefel.",
                                "Jagt einen Schmetterling, fängt ihn, lässt ihn frei.",
                                "Gießt den Boden, bis eine Blume wächst.", "Eine Umarmung. Autsch.",
                                "Wendet einen Pfannkuchen. Meistens fängt es ihn.", "Eine Kerze, ein Wunsch, ein Bissen.",
                                "Einmal lecken, dann Zuckerschock.", "Tadaa! Einfach so.",
                                "Das traurigste Lied, mit echten Tränen.", "Dribbeln, Dunk, swisch. Oder klonk.",
                                "Drehen und drehen… gelöst, oder nicht.", "Schütteln und fragen. Sie antwortet.",
                                "Läuft gegen den Wind, damit es sich dreht.", "Zielt auf nichts, trifft etwas.",
                                "Quietsch, quietsch, ein Hund… peng.", "Schreibt seinen Namen in Funken.",
                                "Legt den Beat auf und breakdanct.", "Baut einen Turm. Er fällt um.",
                                "Ein kleiner Schritt, ganz langsam.", "Wirft den Hut in den Himmel.",
                                "Der Frühling folgt ihm überallhin.", "Entdeckt einen Vogel, weit, weit weg.",
                                "Hoch, hoch… und eine Pose.", "Größer als alle, für einen Moment."])
        case .fr:
            return .init(items: ["Canne à pêche", "Filet à papillons", "Arrosoir", "Cactus en pot", "Poêle", "Cupcake",
                                 "Sucette", "Trompette", "Violon", "Ballon de basket", "Cube de couleurs", "Boule des réponses",
                                 "Moulin à vent", "Lance-pierre", "Chien en ballon", "Cierge magique", "Radiocassette",
                                 "Casque de chantier", "Casque d’astronaute", "Mortier de diplômé", "Couronne de fleurs",
                                 "Jumelles", "Super cape", "Échasses"],
                         gags: ["Lance, attend… un poisson, ou une vieille botte.", "Poursuit un papillon, l’attrape, le relâche.",
                                "Arrose le sol jusqu’à ce qu’une fleur pousse.", "Un câlin. Aïe.",
                                "Fait sauter une crêpe. La rattrape, en général.", "Une bougie, un vœu, une seule bouchée.",
                                "Un coup de langue, puis l’euphorie du sucre.", "Ta-daa ! Pour rien.",
                                "La chanson la plus triste, avec de vraies larmes.", "Dribble, dunk, swish. Ou clang.",
                                "Tourne et tourne… résolu, ou pas.", "Secouez et demandez. Elle répond.",
                                "Court contre le vent pour le faire tourner.", "Vise le vide, touche quelque chose.",
                                "Couic, couic, un chien… pop.", "Écrit son nom en étincelles.",
                                "Lance le son et fait du breakdance.", "Construit une tour. Elle tombe.",
                                "Un petit pas, très lentement.", "Lance son mortier vers le ciel.",
                                "Le printemps le suit partout.", "Repère un oiseau très, très loin.",
                                "Plus haut… et une pose.", "Plus grand que tout le monde, un instant."])
        case .it:
            return .init(items: ["Canna da pesca", "Retino per farfalle", "Annaffiatoio", "Cactus in vaso", "Padella", "Cupcake",
                                 "Lecca-lecca", "Tromba", "Violino", "Pallone da basket", "Cubo colorato", "Sfera dei responsi",
                                 "Girandola", "Fionda", "Cane di palloncino", "Stellina scintillante", "Stereo portatile",
                                 "Casco da cantiere", "Casco da astronauta", "Tocco da laurea", "Corona di fiori", "Binocolo",
                                 "Supermantello", "Trampoli"],
                         gags: ["Lancia, aspetta… un pesce, o un vecchio stivale.", "Insegue una farfalla, la prende e la libera.",
                                "Annaffia il pavimento finché spunta un fiore.", "Un abbraccio. Ahi.",
                                "Fa saltare un pancake. Di solito lo riprende.", "Una candelina, un desiderio, un morso solo.",
                                "Una leccata, poi la carica di zucchero.", "Ta-dah! Senza motivo.",
                                "La canzone più triste, con lacrime vere.", "Palleggio, schiacciata, ciuff. O clang.",
                                "Gira e rigira… risolto, o no.", "Scuotila e chiedi. Risponde.",
                                "Corre controvento per farla girare.", "Mira al nulla, colpisce qualcosa.",
                                "Squik, squik, un cane… pop.", "Scrive il suo nome con le scintille.",
                                "Fa partire il ritmo e balla breakdance.", "Costruisce una torre. Crolla.",
                                "Un piccolo passo, lentissimo.", "Lancia il tocco verso il cielo.",
                                "La primavera lo segue ovunque.", "Avvista un uccello lontano lontano.",
                                "Su, su… e una posa.", "Più alto di tutti, per un attimo."])
        case .sk:
            return .init(items: ["Rybársky prút", "Sieťka na motýle", "Krhla", "Kaktus v kvetináči", "Panvica", "Cupcake",
                                 "Lízatko", "Trúbka", "Husle", "Basketbalová lopta", "Farebná kocka", "Guľa odpovedí",
                                 "Veterník", "Prak", "Balónový psík", "Prskavka", "Kazetový prehrávač", "Prilba staviteľa",
                                 "Astronautská prilba", "Promočná čiapka", "Kvetinový venček", "Ďalekohľad", "Superplášť",
                                 "Chodúle"],
                         gags: ["Nahodí, čaká… ryba alebo stará čižma.", "Naháňa motýľa, chytí ho a pustí.",
                                "Polieva zem, kým nevyrastie kvet.", "Objatie. Au.",
                                "Prehodí palacinku. Väčšinou ju chytí.", "Sviečka, želanie, jedno hryznutie.",
                                "Jedno olíznutie a cukrový nával.", "Ta-dá! Len tak.",
                                "Najsmutnejšia pieseň, so skutočnými slzami.", "Dribling, smeč, švih. Alebo cink.",
                                "Točí a točí… vyriešené, alebo nie.", "Zatras a opýtaj sa. Odpovie.",
                                "Beží proti vetru, aby sa točil.", "Mieri na nič, trafí niečo.",
                                "Pisk, pisk, psík… puk.", "Píše svoje meno iskrami.",
                                "Pustí rytmus a tancuje breakdance.", "Postaví vežu. Spadne.",
                                "Malý krok, veľmi pomaly.", "Vyhodí čiapku do neba.",
                                "Jar ho všade sprevádza.", "Zbadá vtáka ďaleko, ďaleko.",
                                "Hore, hore… a póza.", "Vyšší než všetci, na chvíľu."])
        case .uk:
            return .init(items: ["Вудка", "Сачок для метеликів", "Лійка", "Кактус у горщику", "Сковорідка", "Капкейк",
                                 "Льодяник", "Труба", "Скрипка", "Баскетбольний м’яч", "Кольоровий кубик", "Куля відповідей",
                                 "Вітрячок", "Рогатка", "Песик з кульки", "Бенгальський вогник", "Магнітофон",
                                 "Будівельна каска", "Шолом астронавта", "Випускна шапочка", "Віночок", "Бінокль",
                                 "Суперплащ", "Ходулі"],
                         gags: ["Закидає, чекає… риба чи старий чобіт.", "Ганяється за метеликом, ловить і відпускає.",
                                "Поливає підлогу, поки не виросте квітка.", "Обіймає його. Ой.",
                                "Підкидає млинець. Зазвичай ловить.", "Свічка, бажання, один укус.",
                                "Один лиз — і цукровий заряд.", "Та-дам! Просто так.",
                                "Найсумніша пісня, зі справжніми сльозами.", "Ведення, данк, шурх. Або дзень.",
                                "Крутить і крутить… зібрав чи ні.", "Струсни й запитай. Вона відповість.",
                                "Біжить проти вітру, щоб він крутився.", "Цілиться в ніщо, влучає в щось.",
                                "Рип, рип, песик… бах.", "Пише своє ім’я іскрами.",
                                "Вмикає біт і танцює брейк.", "Будує вежу. Вона падає.",
                                "Маленький крок, дуже повільно.", "Підкидає шапочку в небо.",
                                "Весна ходить за ним слідом.", "Помічає птаха далеко-далеко.",
                                "Вгору, вгору… і поза.", "Вищий за всіх, на мить."])
        case .ru:
            return .init(items: ["Удочка", "Сачок для бабочек", "Лейка", "Кактус в горшке", "Сковородка", "Капкейк",
                                 "Леденец", "Труба", "Скрипка", "Баскетбольный мяч", "Цветной кубик", "Шар ответов",
                                 "Вертушка", "Рогатка", "Собачка из шарика", "Бенгальский огонь", "Магнитофон",
                                 "Строительная каска", "Шлем астронавта", "Выпускная шапочка", "Венок", "Бинокль",
                                 "Суперплащ", "Ходули"],
                         gags: ["Забрасывает, ждёт… рыба или старый сапог.", "Гоняется за бабочкой, ловит и отпускает.",
                                "Поливает пол, пока не вырастет цветок.", "Обнимает его. Ай.",
                                "Подбрасывает блин. Обычно ловит.", "Свечка, желание, один укус.",
                                "Один лизок — и сахарный заряд.", "Та-дам! Просто так.",
                                "Самая грустная песня, с настоящими слезами.", "Дриблинг, данк, шурх. Или дзынь.",
                                "Крутит и крутит… собрал или нет.", "Встряхни и спроси. Он ответит.",
                                "Бежит против ветра, чтобы она крутилась.", "Целится в никуда, попадает во что-то.",
                                "Скрип, скрип, собачка… бах.", "Пишет своё имя искрами.",
                                "Включает бит и танцует брейк.", "Строит башню. Она падает.",
                                "Маленький шаг, очень медленно.", "Подбрасывает шапочку в небо.",
                                "Весна ходит за ним по пятам.", "Замечает птицу далеко-далеко.",
                                "Вверх, вверх… и поза.", "Выше всех, на мгновение."])
        case .tr:
            return .init(items: ["Olta", "Kelebek ağı", "Sulama kabı", "Saksıda kaktüs", "Tava", "Cupcake",
                                 "Lolipop", "Trompet", "Keman", "Basketbol topu", "Renkli küp", "Cevap küresi",
                                 "Fırıldak", "Sapan", "Balon köpek", "Maytap", "Teyp", "Baret",
                                 "Astronot kaskı", "Mezuniyet kepi", "Çiçek tacı", "Dürbün", "Süper pelerin", "Ayaklık"],
                         gags: ["Atar, bekler… bir balık ya da eski bir çizme.", "Bir kelebeği kovalar, yakalar, bırakır.",
                                "Bir çiçek çıkana kadar yeri sular.", "Ona sarılır. Ah.",
                                "Bir krep çevirir. Genelde yakalar.", "Bir mum, bir dilek, tek bir ısırık.",
                                "Bir yalayış, sonra şeker coşkusu.", "Ta-taa! Sebepsiz yere.",
                                "En hüzünlü şarkı, gerçek gözyaşlarıyla.", "Sektir, smaç, şık. Ya da tın.",
                                "Çevirir de çevirir… çözdü ya da çözemedi.", "Salla ve sor. Cevap verir.",
                                "Dönsün diye rüzgâra karşı koşar.", "Hiçliğe nişan alır, bir şeyi vurur.",
                                "Gıcır gıcır, bir köpek… pat.", "Adını kıvılcımlarla yazar.",
                                "Ritmi açar ve breakdance yapar.", "Bir kule yapar. Yıkılır.",
                                "Küçük bir adım, çok yavaşça.", "Kepini göğe fırlatır.",
                                "Bahar onu her yerde takip eder.", "Çok uzakta bir kuş görür.",
                                "Yukarı, yukarı… ve poz.", "Bir anlığına herkesten uzun."])
        case .ja:
            return .init(items: ["釣りざお", "虫とり網", "じょうろ", "鉢植えサボテン", "フライパン", "カップケーキ",
                                 "ペロペロキャンディ", "トランペット", "バイオリン", "バスケットボール", "カラーキューブ", "こたえの玉",
                                 "かざぐるま", "スリングショット", "バルーンドッグ", "手持ち花火", "ラジカセ", "工事ヘルメット",
                                 "宇宙飛行士ヘルメット", "卒業帽", "花かんむり", "双眼鏡", "スーパーマント", "竹馬"],
                         gags: ["投げて、待つ…魚か、古いブーツ。", "チョウを追いかけ、つかまえて、はなす。",
                                "花が咲くまで床に水やり。", "ぎゅっとハグ。いたっ。",
                                "パンケーキをひっくり返す。たいていキャッチ。", "ろうそく、ねがいごと、ひとくち。",
                                "ひとなめで、シュガーラッシュ。", "ジャジャーン！とくに理由なし。",
                                "いちばん悲しい曲、本物の涙つき。", "ドリブル、ダンク、スパッ。またはガコン。",
                                "回して回して…そろった、かも。", "振って聞けば、こたえてくれる。",
                                "風に向かって走って回す。", "何もないところをねらって、何かに当たる。",
                                "キュッキュッ、ワンちゃん…パン！", "火花で自分の名前を書く。",
                                "ビートを流してブレイクダンス。", "塔をつくる。たおれる。",
                                "小さな一歩を、ゆっくりと。", "帽子を空に投げる。",
                                "春がどこまでもついてくる。", "ずっと遠くの鳥を見つける。",
                                "上へ上へ…そしてポーズ。", "ほんの一瞬、だれよりも背が高い。"])
        case .ko:
            return .init(items: ["낚싯대", "잠자리채", "물뿌리개", "화분 선인장", "프라이팬", "컵케이크",
                                 "막대사탕", "트럼펫", "바이올린", "농구공", "컬러 큐브", "대답 구슬",
                                 "바람개비", "새총", "풍선 강아지", "불꽃 막대", "붐박스", "안전모",
                                 "우주비행사 헬멧", "학사모", "화관", "쌍안경", "슈퍼 망토", "죽마"],
                         gags: ["던지고, 기다리고… 물고기, 아니면 낡은 장화.", "나비를 쫓아가 잡았다가 놓아줘요.",
                                "꽃이 필 때까지 바닥에 물을 줘요.", "꼭 안아 줘요. 아야.",
                                "팬케이크를 뒤집어요. 보통은 받아요.", "촛불 하나, 소원 하나, 한 입.",
                                "한 번 핥고 당 충전.", "짜잔! 그냥요.",
                                "가장 슬픈 노래, 진짜 눈물과 함께.", "드리블, 덩크, 슉. 아니면 쾅.",
                                "돌리고 돌리고… 맞췄을까?", "흔들고 물어보면 대답해요.",
                                "돌아가라고 바람을 향해 달려요.", "아무것도 없는 데를 겨눴는데 뭔가 맞아요.",
                                "뽁뽁, 강아지… 펑!", "불꽃으로 자기 이름을 써요.",
                                "비트를 틀고 브레이크댄스.", "탑을 쌓아요. 무너져요.",
                                "작은 한 걸음, 아주 천천히.", "학사모를 하늘로 던져요.",
                                "봄이 어디든 따라와요.", "아주 멀리 있는 새를 찾아요.",
                                "위로, 위로… 그리고 포즈.", "잠깐 동안 누구보다 키가 커요."])
        case .zhHans:
            return .init(items: ["钓竿", "捕蝶网", "洒水壶", "盆栽仙人掌", "平底锅", "纸杯蛋糕",
                                 "棒棒糖", "小号", "小提琴", "篮球", "彩色方块", "答案球",
                                 "风车", "弹弓", "气球小狗", "仙女棒", "录音机", "安全帽",
                                 "宇航员头盔", "学士帽", "花环", "双筒望远镜", "超级披风", "高跷"],
                         gags: ["抛竿、等待……一条鱼，或一只旧靴子。", "追着蝴蝶跑，抓到又放走。",
                                "浇地板，直到长出一朵花。", "抱一下。哎哟。",
                                "翻煎饼。通常都接得住。", "一根蜡烛，一个愿望，一口吃掉。",
                                "舔一口，糖分爆棚。", "哒哒！没有理由。",
                                "最悲伤的曲子，配上真眼泪。", "运球、扣篮、唰。或者哐。",
                                "转啊转……拼好了，也许没有。", "摇一摇再问，它会回答。",
                                "逆风奔跑让它转起来。", "瞄准空气，打中了什么。",
                                "吱吱，一只小狗……啪！", "用火花写自己的名字。",
                                "放起节拍跳霹雳舞。", "搭一座塔。塌了。",
                                "一小步，慢慢走。", "把帽子抛向天空。",
                                "春天一路跟着它。", "发现很远很远的一只鸟。",
                                "飞起来……摆个姿势。", "有那么一刻比谁都高。"])
        case .zhHK, .zhTW:
            return .init(items: ["釣竿", "捕蝶網", "澆水壺", "盆栽仙人掌", "平底鍋", "杯子蛋糕",
                                 "棒棒糖", "小號", "小提琴", "籃球", "彩色方塊", "答案球",
                                 "風車", "彈弓", "氣球小狗", "仙女棒", "收錄音機", "安全帽",
                                 "太空人頭盔", "學士帽", "花環", "雙筒望遠鏡", "超級披風", "高蹺"],
                         gags: ["拋竿、等待……一條魚，或一隻舊靴子。", "追著蝴蝶跑，抓到又放走。",
                                "澆地板，直到長出一朵花。", "抱一下。哎喲。",
                                "翻鬆餅。通常都接得住。", "一根蠟燭，一個願望，一口吃掉。",
                                "舔一口，糖分爆棚。", "噠噠！沒有理由。",
                                "最悲傷的曲子，配上真眼淚。", "運球、灌籃、唰。或者哐。",
                                "轉啊轉……拼好了，也許沒有。", "搖一搖再問，它會回答。",
                                "逆風奔跑讓它轉起來。", "瞄準空氣，打中了什麼。",
                                "吱吱，一隻小狗……啪！", "用火花寫自己的名字。",
                                "放起節拍跳霹靂舞。", "搭一座塔。塌了。",
                                "一小步，慢慢走。", "把帽子拋向天空。",
                                "春天一路跟著它。", "發現很遠很遠的一隻鳥。",
                                "飛起來……擺個姿勢。", "有那麼一刻比誰都高。"])
        }
    }
}
