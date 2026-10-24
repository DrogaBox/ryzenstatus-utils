// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The companion out on the desktop: its switches in Settings and the menu a
/// right click on it opens.
struct NotchMascotDesktopStrings {
    let title: String
    let caption: String
    let excursions: String
    let excursionsCaption: String
    /// The friend that lives with it in the island and on the desktop, and
    /// the choice of no one.
    let friend: String
    let nobody: String
    /// What the friend wears, and the choice of leaving it to the friend.
    let friendItem: String
    let friendItemOwn: String
    /// The two out on the desktop playing together now and then.
    let plays: String
    let playsCaption: String
    /// The friend's own colors, beside its item.
    var friendColors: String = "The friend's colors"
    var friendColorsSame: String = "Its companion's"
    var friendCustomColor: String = "Hand-picked"
    /// Dress-up play: by itself, it puts on anything it owns for a while.
    var dressUp: String = "Play with its wardrobe"
    var dressUpCaption: String =
        "Out on the desktop, now and then it digs into everything it owns and wears whatever it feels like for a minute — then back to what you picked. What it wears the rest of the day stays your choice."
    let goHome: String
    let stayPut: String
    let settings: String
}

extension FeatureStrings {
    static func notchMascotDesktop(_ language: AppLanguage) -> NotchMascotDesktopStrings {
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

extension NotchMascotDesktopStrings {
    static let enUS = NotchMascotDesktopStrings(
        title: "Come out onto the desktop",
        caption: "Drag the companion down out of the closed island and it walks around the desktop. Click to pat it, drag it about, throw it, double-click it or drop it back on the island to send it home.",
        excursions: "Go for walks on its own",
        excursionsCaption: "Now and then it hops out of the island by itself, wanders about for a minute or two and goes back in.",
        friend: "A friend keeps it company",
        nobody: "No one",
        friendItem: "What the friend wears",
        friendItemOwn: "Its own pick",
        plays: "They play together",
        playsCaption: "Now and then the two out on the desktop duel with blades of light, throw energy at each other, power up, dance, high-five, play tag, leapfrog, hug, trade gifts or nap side by side. In the island they wave across it, toss hearts, stars and snowballs to each other, and play with what they wear.",
        dressUp: "Play with its wardrobe",
        dressUpCaption: "Out on the desktop, now and then it digs into everything it owns and wears whatever it feels like for a minute — then back to what you picked. What it wears the rest of the day stays your choice.",
        goHome: "Back to the Island",
        stayPut: "Stay Put",
        settings: "Companion Settings…")
    static let ptBR = NotchMascotDesktopStrings(
        title: "Sair para a mesa",
        caption: "Arraste o companheiro para baixo, para fora da ilha fechada, e ele passeia pela mesa. Clique para fazer carinho, arraste, arremesse, clique duas vezes ou solte-o sobre a ilha para mandá-lo de volta.",
        excursions: "Passear sozinho",
        excursionsCaption: "De vez em quando ele pula da ilha por conta própria, passeia um ou dois minutos e volta.",
        friend: "Um amigo faz companhia",
        nobody: "Ninguém",
        friendItem: "O que o amigo usa",
        friendItemOwn: "Escolha dele",
        plays: "Brincam juntos",
        playsCaption: "De vez em quando os dois na mesa duelam com espadas de luz, lançam energia um no outro, se transformam, dançam, batem as mãos, brincam de pega-pega, pulam um sobre o outro, se abraçam, trocam presentes ou cochilam lado a lado. Na ilha eles acenam de um lado ao outro, jogam corações, estrelas e bolas de neve um para o outro e brincam com o que estão usando.",
        goHome: "Voltar para a ilha",
        stayPut: "Ficar parado",
        settings: "Ajustes do companheiro…")
    static let tr = NotchMascotDesktopStrings(
        title: "Masaüstüne çıksın",
        caption: "Arkadaşı kapalı adadan aşağı sürükleyin, masaüstünde dolaşsın. Okşamak için tıklayın; sürükleyin, fırlatın, geri göndermek için çift tıklayın ya da adanın üzerine bırakın.",
        excursions: "Kendi başına gezsin",
        excursionsCaption: "Ara sıra adadan kendiliğinden atlar, bir iki dakika dolaşır ve geri döner.",
        friend: "Bir arkadaşı ona eşlik etsin",
        nobody: "Kimse",
        friendItem: "Arkadaşın giydiği",
        friendItemOwn: "Kendi seçimi",
        plays: "Birlikte oynasınlar",
        playsCaption: "Masaüstündeki ikili ara sıra ışın kılıçlarıyla düello yapar, birbirine enerji fırlatır, güçlenir, dans eder, çak yapar, kovalamaca oynar, birbirinin üstünden atlar, sarılır, hediye verir ya da yan yana kestirir. Adada birbirlerine el sallar, kalpler, yıldızlar ve kartopları atar, giydikleriyle oynarlar.",
        goHome: "Adaya dön",
        stayPut: "Yerinde kal",
        settings: "Arkadaş ayarları…")
    static let ru = NotchMascotDesktopStrings(
        title: "Выходить на рабочий стол",
        caption: "Вытяните компаньона вниз из закрытого острова, и он будет гулять по рабочему столу. Щелчок — погладить; его можно перетаскивать и бросать, а двойной щелчок или отпускание над островом отправляет его домой.",
        excursions: "Гулять самостоятельно",
        excursionsCaption: "Время от времени он сам выпрыгивает из острова, гуляет минуту-другую и возвращается.",
        friend: "Друг составляет компанию",
        nobody: "Никто",
        friendItem: "Что носит друг",
        friendItemOwn: "Сам выберет",
        plays: "Играют вместе",
        playsCaption: "Время от времени двое на рабочем столе сражаются световыми мечами, бросают друг в друга энергию, набирают силу, танцуют, дают пять, играют в салки и чехарду, обнимаются, дарят подарки или дремлют рядом. На острове они машут друг другу, перебрасываются сердечками, звёздами и снежками и играют с тем, что на них надето.",
        goHome: "Вернуться на остров",
        stayPut: "Стоять на месте",
        settings: "Настройки компаньона…")
    static let es = NotchMascotDesktopStrings(
        title: "Salir al escritorio",
        caption: "Arrastra al compañero hacia abajo, fuera de la isla cerrada, y se pondrá a pasear por el escritorio. Haz clic para acariciarlo; puedes arrastrarlo y lanzarlo, y con doble clic o soltándolo sobre la isla vuelve a casa.",
        excursions: "Salir a pasear solo",
        excursionsCaption: "De vez en cuando salta de la isla por su cuenta, pasea un minuto o dos y vuelve.",
        friend: "Le acompaña un amigo",
        nobody: "Nadie",
        friendItem: "Lo que lleva el amigo",
        friendItemOwn: "Lo elige él",
        plays: "Juegan entre ellos",
        playsCaption: "De vez en cuando los dos en el escritorio se baten en duelo con espadas de luz, se lanzan ondas de energía, se transforman, bailan, chocan los cinco, juegan a pillarse, saltan uno sobre el otro, se abrazan, se hacen regalos o duermen la siesta juntos. En la isla se saludan de lado a lado, se lanzan corazones, estrellas y bolas de nieve, y juegan con lo que llevan puesto.",
        friendColors: "Los colores del amigo",
        friendColorsSame: "Los de su compañero",
        friendCustomColor: "A mano",
        dressUp: "Jugar con su armario",
        dressUpCaption: "En el escritorio, de vez en cuando rebusca entre todo lo que tiene y se pone lo que le apetece un ratito — y luego vuelve a lo que tú elegiste. Lo que lleva el resto del día sigue siendo cosa tuya.",
        goHome: "Volver a la isla",
        stayPut: "Quedarse quieto",
        settings: "Ajustes del compañero…")
    static let sk = NotchMascotDesktopStrings(
        title: "Vychádzať na plochu",
        caption: "Potiahnite spoločníka nadol zo zatvoreného ostrova a bude sa prechádzať po ploche. Kliknutím ho pohladkáte; môžete ho ťahať a hodiť, dvojklikom alebo pustením nad ostrovom sa vráti domov.",
        excursions: "Chodiť na prechádzky sám",
        excursionsCaption: "Občas sám vyskočí z ostrova, minútu či dve sa prechádza a vráti sa.",
        friend: "Robí mu spoločnosť kamarát",
        nobody: "Nikto",
        friendItem: "Čo nosí kamarát",
        friendItemOwn: "Vyberie si sám",
        plays: "Hrajú sa spolu",
        playsCaption: "Občas sa tí dvaja na ploche pobijú svetelnými mečmi, hádžu po sebe energiu, nabíjajú sa, tancujú, plesnú si, hrajú naháňačku a skákanie cez seba, objímajú sa, obdarúvajú sa alebo si spolu zdriemnu. Na ostrove si zakývajú, hádžu si srdiečka, hviezdy a snehové gule a hrajú sa s tým, čo majú na sebe.",
        goHome: "Späť na ostrov",
        stayPut: "Zostať na mieste",
        settings: "Nastavenia spoločníka…")
    static let de = NotchMascotDesktopStrings(
        title: "Auf den Schreibtisch kommen",
        caption: "Zieh den Begleiter aus der geschlossenen Insel nach unten, dann spaziert er über den Schreibtisch. Klick ihn zum Streicheln an, zieh und wirf ihn herum; ein Doppelklick oder das Loslassen über der Insel schickt ihn nach Hause.",
        excursions: "Allein spazieren gehen",
        excursionsCaption: "Ab und zu hüpft er von selbst aus der Insel, läuft ein, zwei Minuten herum und kehrt zurück.",
        friend: "Ein Freund leistet ihm Gesellschaft",
        nobody: "Niemand",
        friendItem: "Was der Freund trägt",
        friendItemOwn: "Sucht es selbst aus",
        plays: "Sie spielen miteinander",
        playsCaption: "Ab und zu duellieren sich die beiden auf dem Schreibtisch mit Lichtklingen, werfen sich Energie zu, laden sich auf, tanzen, klatschen ab, spielen Fangen und Bockspringen, umarmen sich, beschenken sich oder halten nebeneinander ein Nickerchen. In der Insel winken sie sich zu, werfen sich Herzen, Sterne und Schneebälle zu und spielen mit dem, was sie tragen.",
        goHome: "Zurück zur Insel",
        stayPut: "Stehen bleiben",
        settings: "Begleiter-Einstellungen …")
    static let fr = NotchMascotDesktopStrings(
        title: "Sortir sur le bureau",
        caption: "Faites glisser le compagnon vers le bas, hors de l’île fermée, et il se promène sur le bureau. Cliquez pour le caresser, faites-le glisser, lancez-le ; un double-clic ou un lâcher sur l’île le renvoie chez lui.",
        excursions: "Se promener tout seul",
        excursionsCaption: "De temps en temps, il saute de l’île tout seul, se promène une minute ou deux et revient.",
        friend: "Un ami lui tient compagnie",
        nobody: "Personne",
        friendItem: "Ce que porte l'ami",
        friendItemOwn: "Son propre choix",
        plays: "Ils jouent ensemble",
        playsCaption: "De temps en temps, les deux sur le bureau croisent des lames de lumière, se lancent de l'énergie, se transforment, dansent, se tapent dans la main, jouent à chat et à saute-mouton, se font un câlin, s'offrent des cadeaux ou font la sieste côte à côte. Dans l'île, ils se saluent d'un bout à l'autre, se lancent cœurs, étoiles et boules de neige, et jouent avec ce qu'ils portent.",
        goHome: "Retour à l’île",
        stayPut: "Ne pas bouger",
        settings: "Réglages du compagnon…")
    static let it = NotchMascotDesktopStrings(
        title: "Uscire sulla scrivania",
        caption: "Trascina il compagno verso il basso, fuori dall’isola chiusa, e passeggerà sulla scrivania. Fai clic per accarezzarlo, trascinalo, lancialo; un doppio clic o rilasciarlo sull’isola lo rimanda a casa.",
        excursions: "Passeggiare da solo",
        excursionsCaption: "Ogni tanto salta fuori dall’isola da solo, passeggia un minuto o due e torna.",
        friend: "Un amico gli fa compagnia",
        nobody: "Nessuno",
        friendItem: "Cosa indossa l'amico",
        friendItemOwn: "Lo sceglie lui",
        plays: "Giocano insieme",
        playsCaption: "Ogni tanto i due sulla scrivania duellano con spade di luce, si lanciano energia, si potenziano, ballano, si battono il cinque, giocano ad acchiapparella e alla cavallina, si abbracciano, si fanno regali o schiacciano un pisolino vicini. Nell'isola si salutano da un lato all'altro, si lanciano cuori, stelle e palle di neve e giocano con quello che indossano.",
        goHome: "Torna all’isola",
        stayPut: "Resta fermo",
        settings: "Impostazioni del compagno…")
    static let ja = NotchMascotDesktopStrings(
        title: "デスクトップに出てくる",
        caption: "閉じたアイランドからコンパニオンを下へドラッグすると、デスクトップを歩き回ります。クリックでなでて、ドラッグや投げることもできます。ダブルクリックするかアイランドの上で離すと帰ります。",
        excursions: "ひとりで散歩する",
        excursionsCaption: "ときどき自分でアイランドから飛び出し、1〜2分歩き回ってから戻ります。",
        friend: "友だちが一緒にいる",
        nobody: "なし",
        friendItem: "友だちの着るもの",
        friendItemOwn: "おまかせ",
        plays: "一緒に遊ぶ",
        playsCaption: "デスクトップの2匹がときどき光の剣で決闘したり、エネルギー波を撃ち合ったり、パワーアップしたり、踊ったり、ハイタッチ、鬼ごっこ、馬跳び、ハグ、プレゼント交換、並んでお昼寝をしたりします。アイランドでは端から手を振り合い、ハートや星や雪玉を投げ合い、身につけたもので遊びます。",
        goHome: "アイランドに戻る",
        stayPut: "その場にいる",
        settings: "コンパニオン設定…")
    static let ko = NotchMascotDesktopStrings(
        title: "데스크탑으로 나오기",
        caption: "닫힌 아일랜드에서 동반자를 아래로 끌어내면 데스크탑을 돌아다닙니다. 클릭하면 쓰다듬고, 끌거나 던질 수 있으며, 이중 클릭하거나 아일랜드 위에 놓으면 돌아갑니다.",
        excursions: "혼자 산책하기",
        excursionsCaption: "가끔 스스로 아일랜드에서 뛰어나와 1~2분 돌아다니다가 돌아갑니다.",
        friend: "친구가 함께 지내기",
        nobody: "없음",
        friendItem: "친구가 착용할 것",
        friendItemOwn: "친구가 직접 고름",
        plays: "함께 놀기",
        playsCaption: "데스크톱의 둘이 가끔 빛의 검으로 결투하고, 에너지파를 주고받고, 파워업하고, 춤추고, 하이파이브하고, 술래잡기와 등 짚고 넘기를 하고, 껴안고, 선물을 주고받거나 나란히 낮잠을 잡니다. 아일랜드에서는 양쪽에서 손을 흔들고, 하트와 별과 눈덩이를 주고받으며, 착용한 것으로 놀아요.",
        goHome: "아일랜드로 돌아가기",
        stayPut: "가만히 있기",
        settings: "동반자 설정…")
    static let zhHans = NotchMascotDesktopStrings(
        title: "到桌面上来",
        caption: "把伙伴从关闭的灵动岛向下拖出，它就会在桌面上走来走去。点按可以摸摸它，也可以拖动、扔出去；连按两下或把它放回岛上，它就回家。",
        excursions: "自己出去散步",
        excursionsCaption: "它偶尔会自己从岛里跳出来，溜达一两分钟再回去。",
        friend: "有个朋友作伴",
        nobody: "无",
        friendItem: "伙伴的穿戴",
        friendItemOwn: "让它自己选",
        plays: "一起玩耍",
        playsCaption: "桌面上的两个伙伴时不时会用光剑决斗、互相发射能量波、变身、跳舞、击掌、玩捉人和跳山羊、拥抱、互送礼物，或者并排打个盹。在灵动岛里，它们隔着岛挥手，互相抛爱心、星星和雪球，还会拿身上的穿戴玩耍。",
        goHome: "回到岛上",
        stayPut: "待在原地",
        settings: "伙伴设置…")
    static let zhTW = NotchMascotDesktopStrings(
        title: "到桌面上來",
        caption: "把夥伴從關閉的動態島向下拖出，它就會在桌面上走來走去。按一下可以摸摸它，也可以拖曳、丟出去；按兩下或把它放回島上，它就回家。",
        excursions: "自己出去散步",
        excursionsCaption: "它偶爾會自己從島裡跳出來，逛個一兩分鐘再回去。",
        friend: "有個朋友作伴",
        nobody: "無",
        friendItem: "夥伴的穿戴",
        friendItemOwn: "讓它自己選",
        plays: "一起玩耍",
        playsCaption: "桌面上的兩個夥伴不時會用光劍決鬥、互相發射能量波、變身、跳舞、擊掌、玩鬼抓人和跳馬背、擁抱、互送禮物，或者並排打個盹。在動態島裡，它們隔著島揮手，互相拋愛心、星星和雪球，還會拿身上的穿戴玩耍。",
        goHome: "回到島上",
        stayPut: "待在原地",
        settings: "夥伴設定⋯")
    static let zhHK = NotchMascotDesktopStrings(
        title: "到桌面上來",
        caption: "把夥伴從關閉的動態島向下拖出，它就會在桌面上走來走去。按一下可以摸摸它，也可以拖曳、掉出去；按兩下或把它放回島上，它就回家。",
        excursions: "自己出去散步",
        excursionsCaption: "它間中會自己從島裡跳出來，逛一兩分鐘再回去。",
        friend: "有個朋友作伴",
        nobody: "無",
        friendItem: "夥伴的穿戴",
        friendItemOwn: "讓它自己揀",
        plays: "一齊玩",
        playsCaption: "桌面上兩個夥伴不時會用光劍決鬥、互相發射能量波、變身、跳舞、擊掌、玩捉迷藏同跳馬、攬住對方、互送禮物，或者並排瞓個晏覺。喺動態島入面，佢哋隔住島揮手，互相拋心心、星星同雪球，仲會拎身上嘅穿戴嚟玩。",
        goHome: "回到島上",
        stayPut: "留在原地",
        settings: "夥伴設定⋯")
    static let uk = NotchMascotDesktopStrings(
        title: "Виходити на робочий стіл",
        caption: "Витягніть компаньйона вниз із закритого острова, і він гулятиме робочим столом. Клацніть, щоб погладити; його можна перетягувати й кидати, а подвійне клацання чи відпускання над островом відправляє його додому.",
        excursions: "Гуляти самостійно",
        excursionsCaption: "Час від часу він сам вистрибує з острова, гуляє хвилину-другу й повертається.",
        friend: "Друг складає компанію",
        nobody: "Ніхто",
        friendItem: "Що носить друг",
        friendItemOwn: "Обере сам",
        plays: "Граються разом",
        playsCaption: "Час від часу двоє на робочому столі б'ються світловими мечами, кидають одне в одного енергію, набирають силу, танцюють, дають п'ять, граються в квача й чехарду, обіймаються, дарують подарунки або дрімають поруч. На острові вони махають одне одному, перекидаються сердечками, зірками й сніжками та граються з тим, що на них вдягнено.",
        goHome: "Повернутися на острів",
        stayPut: "Стояти на місці",
        settings: "Параметри компаньйона…")
}
