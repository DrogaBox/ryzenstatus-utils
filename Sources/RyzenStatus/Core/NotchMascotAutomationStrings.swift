// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The companion's extra styles, its automatic reactions and the moments
/// that show them in the Settings preview.
struct NotchMascotAutomationStrings {
    let chip: String
    let fan: String
    let cat: String
    let ghost: String
    let slime: String
    /// The switch for every automatic reaction, and what it does.
    let automatic: String
    let automaticHint: String
    /// One switch for each kind of automatic reaction.
    let load: String
    let music: String
    let rest: String
    let coffee: String
    let network: String
    let events: String
    let antics: String
    /// The automatic moments the Settings preview can act out.
    let hardWork: String
    let overheating: String
    let cooledDown: String
    let coffeeBreak: String
    let bigDownload: String
    let cleanedUp: String
    let justSayingHi: String

    /// A style's name, the first two named with the rest of the page.
    func style(_ style: NotchMascotStyle, base: NotchMascotSettingsStrings) -> String {
        switch style {
        case .minimal: return base.minimal
        case .robot: return base.robot
        case .chip: return chip
        case .fan: return fan
        case .cat: return cat
        case .ghost: return ghost
        case .slime: return slime
        // Characters' own names, the same in every language.
        case .cristobal: return "Cristóbal"
        case .whiteRabbit: return "Conejo Blanco"
        }
    }
}

extension FeatureStrings {
    static func notchMascotAutomation(_ language: AppLanguage) -> NotchMascotAutomationStrings {
        switch language {
        case .enUS: return NotchMascotAutomationStrings(
            chip: "Chip", fan: "Fan", cat: "Cat", ghost: "Ghost", slime: "Slime",
            automatic: "Automatic reactions",
            automaticHint: "It reacts on its own to what your Mac is doing: CPU load and heat, music, Keep awake, downloads, the time of day and how long you have been away.",
            load: "Sweat under CPU load and heat", music: "Dance to music",
            rest: "Doze off when you are away or late at night", coffee: "Drink coffee during Keep awake",
            network: "Watch big downloads", events: "Celebrate cleanups, tire on low battery",
            antics: "Little antics now and then",
            hardWork: "CPU working hard", overheating: "CPU running hot", cooledDown: "Load calmed down",
            coffeeBreak: "Coffee break", bigDownload: "Big download", cleanedUp: "Space freed", justSayingHi: "Just saying hi")
        case .ptBR: return NotchMascotAutomationStrings(
            chip: "Chip", fan: "Ventoinha", cat: "Gato", ghost: "Fantasma", slime: "Geleca",
            automatic: "Reações automáticas",
            automaticHint: "Ele reage sozinho ao que o seu Mac está fazendo: carga e calor da CPU, música, Manter acordado, downloads, a hora do dia e quanto tempo você ficou ausente.",
            load: "Suar com carga e calor da CPU", music: "Dançar com a música",
            rest: "Cochilar quando você sai ou tarde da noite", coffee: "Tomar café com Manter acordado",
            network: "Acompanhar downloads grandes", events: "Comemorar limpezas, cansar com bateria fraca",
            antics: "Travessuras de vez em quando",
            hardWork: "CPU trabalhando duro", overheating: "CPU muito quente", cooledDown: "Carga aliviada",
            coffeeBreak: "Pausa para o café", bigDownload: "Download grande", cleanedUp: "Espaço liberado", justSayingHi: "Só dando oi")
        case .es: return NotchMascotAutomationStrings(
            chip: "Chip", fan: "Ventilador", cat: "Gato", ghost: "Fantasma", slime: "Slime",
            automatic: "Reacciones automáticas",
            automaticHint: "Reacciona por su cuenta a lo que hace tu Mac: la carga y la temperatura de la CPU, la música, Mantener activo, las descargas, la hora del día y el tiempo que llevas fuera.",
            load: "Sudar con la carga y el calor de la CPU", music: "Bailar con la música",
            rest: "Dormirse cuando no estás o de madrugada", coffee: "Tomar café con Mantener activo",
            network: "Vigilar las descargas grandes", events: "Celebrar limpiezas, cansarse con poca batería",
            antics: "Travesuras de vez en cuando",
            hardWork: "CPU a tope", overheating: "CPU muy caliente", cooledDown: "La carga bajó",
            coffeeBreak: "Pausa para el café", bigDownload: "Descarga grande", cleanedUp: "Espacio liberado", justSayingHi: "Solo saluda")
        case .sk: return NotchMascotAutomationStrings(
            chip: "Čip", fan: "Ventilátor", cat: "Mačka", ghost: "Duch", slime: "Sliz",
            automatic: "Automatické reakcie",
            automaticHint: "Sám reaguje na to, čo robí váš Mac: záťaž a teplotu CPU, hudbu, Bdelý režim, sťahovanie, dennú dobu a to, ako dlho ste preč.",
            load: "Potiť sa pri záťaži a teple CPU", music: "Tancovať pri hudbe",
            rest: "Zaspať, keď ste preč alebo neskoro v noci", coffee: "Piť kávu počas Bdelého režimu",
            network: "Sledovať veľké sťahovanie", events: "Oslavovať čistenie, unaviť sa pri slabej batérii",
            antics: "Občas malé huncútstva",
            hardWork: "CPU naplno", overheating: "CPU sa prehrieva", cooledDown: "Záťaž opadla",
            coffeeBreak: "Prestávka na kávu", bigDownload: "Veľké sťahovanie", cleanedUp: "Miesto uvoľnené", justSayingHi: "Len pozdrav")
        case .de: return NotchMascotAutomationStrings(
            chip: "Chip", fan: "Lüfter", cat: "Katze", ghost: "Geist", slime: "Schleim",
            automatic: "Automatische Reaktionen",
            automaticHint: "Er reagiert von selbst darauf, was dein Mac gerade tut: CPU-Last und Hitze, Musik, Wachhalten, Downloads, die Tageszeit und wie lange du weg warst.",
            load: "Bei CPU-Last und Hitze schwitzen", music: "Zur Musik tanzen",
            rest: "Einnicken, wenn du weg bist oder spät nachts", coffee: "Beim Wachhalten Kaffee trinken",
            network: "Große Downloads beobachten", events: "Aufräumen feiern, bei schwachem Akku müde werden",
            antics: "Ab und zu kleine Späße",
            hardWork: "CPU unter Volllast", overheating: "CPU wird heiß", cooledDown: "Last abgeklungen",
            coffeeBreak: "Kaffeepause", bigDownload: "Großer Download", cleanedUp: "Speicher freigegeben", justSayingHi: "Einfach Hallo")
        case .fr: return NotchMascotAutomationStrings(
            chip: "Puce", fan: "Ventilateur", cat: "Chat", ghost: "Fantôme", slime: "Slime",
            automatic: "Réactions automatiques",
            automaticHint: "Il réagit tout seul à ce que fait votre Mac : charge et chaleur du processeur, musique, Garder éveillé, téléchargements, moment de la journée et durée de votre absence.",
            load: "Transpirer sous la charge et la chaleur du processeur", music: "Danser sur la musique",
            rest: "S’assoupir pendant votre absence ou tard le soir", coffee: "Boire un café avec Garder éveillé",
            network: "Surveiller les gros téléchargements", events: "Fêter les nettoyages, fatiguer quand la batterie faiblit",
            antics: "Petites facéties de temps en temps",
            hardWork: "Processeur à fond", overheating: "Processeur trop chaud", cooledDown: "La charge est retombée",
            coffeeBreak: "Pause café", bigDownload: "Gros téléchargement", cleanedUp: "Espace libéré", justSayingHi: "Juste un coucou")
        case .it: return NotchMascotAutomationStrings(
            chip: "Chip", fan: "Ventola", cat: "Gatto", ghost: "Fantasma", slime: "Slime",
            automatic: "Reazioni automatiche",
            automaticHint: "Reagisce da solo a ciò che fa il tuo Mac: carico e calore della CPU, musica, Mantieni attivo, download, l’ora del giorno e quanto sei stato via.",
            load: "Sudare con il carico e il calore della CPU", music: "Ballare con la musica",
            rest: "Appisolarsi quando sei via o a tarda notte", coffee: "Bere caffè con Mantieni attivo",
            network: "Seguire i download grandi", events: "Festeggiare le pulizie, stancarsi con la batteria scarica",
            antics: "Piccole marachelle ogni tanto",
            hardWork: "CPU al massimo", overheating: "CPU bollente", cooledDown: "Il carico è calato",
            coffeeBreak: "Pausa caffè", bigDownload: "Download grande", cleanedUp: "Spazio liberato", justSayingHi: "Solo un saluto")
        case .ru: return NotchMascotAutomationStrings(
            chip: "Чип", fan: "Вентилятор", cat: "Кот", ghost: "Призрак", slime: "Слайм",
            automatic: "Автоматические реакции",
            automaticHint: "Он сам реагирует на то, что делает ваш Mac: нагрузку и нагрев CPU, музыку, режим «Не давать Mac уснуть», загрузки, время суток и то, как долго вас не было.",
            load: "Потеть от нагрузки и нагрева CPU", music: "Танцевать под музыку",
            rest: "Засыпать, когда вас нет или поздно ночью", coffee: "Пить кофе, пока Mac не спит",
            network: "Следить за большими загрузками", events: "Радоваться очистке, уставать при низком заряде",
            antics: "Иногда немного шалить",
            hardWork: "CPU работает на полную", overheating: "CPU перегревается", cooledDown: "Нагрузка спала",
            coffeeBreak: "Кофе-брейк", bigDownload: "Большая загрузка", cleanedUp: "Место освобождено", justSayingHi: "Просто привет")
        case .tr: return NotchMascotAutomationStrings(
            chip: "Çip", fan: "Fan", cat: "Kedi", ghost: "Hayalet", slime: "Balçık",
            automatic: "Otomatik tepkiler",
            automaticHint: "Mac’inizin yaptıklarına kendiliğinden tepki verir: CPU yükü ve ısısı, müzik, Uyanık tut, indirmeler, günün saati ve ne kadar süredir uzakta olduğunuz.",
            load: "CPU yükü ve ısısında terle", music: "Müzikle dans et",
            rest: "Uzaktayken veya gece geç saatte uyukla", coffee: "Uyanık tut açıkken kahve iç",
            network: "Büyük indirmeleri izle", events: "Temizliği kutla, pil azalınca yorul",
            antics: "Arada bir küçük şakalar",
            hardWork: "CPU tam yükte", overheating: "CPU çok ısındı", cooledDown: "Yük azaldı",
            coffeeBreak: "Kahve molası", bigDownload: "Büyük indirme", cleanedUp: "Yer açıldı", justSayingHi: "Sadece selam")
        case .ja: return NotchMascotAutomationStrings(
            chip: "チップ", fan: "ファン", cat: "ネコ", ghost: "おばけ", slime: "スライム",
            automatic: "自動リアクション",
            automaticHint: "Macの様子に合わせて自分から反応します：CPUの負荷と温度、音楽、スリープ防止、ダウンロード、時間帯、離席している時間。",
            load: "CPUの負荷や熱で汗をかく", music: "音楽に合わせて踊る",
            rest: "離席中や夜遅くにうとうとする", coffee: "スリープ防止中にコーヒーを飲む",
            network: "大きなダウンロードを見守る", events: "クリーンアップを祝い、バッテリー残量が少ないと疲れる",
            antics: "ときどき小さないたずら",
            hardWork: "CPUフル稼働", overheating: "CPUが高温", cooledDown: "負荷が落ち着いた",
            coffeeBreak: "コーヒーブレイク", bigDownload: "大きなダウンロード", cleanedUp: "空き容量を確保", justSayingHi: "ちょっとごあいさつ")
        case .ko: return NotchMascotAutomationStrings(
            chip: "칩", fan: "팬", cat: "고양이", ghost: "유령", slime: "슬라임",
            automatic: "자동 반응",
            automaticHint: "Mac이 하는 일에 스스로 반응합니다: CPU 부하와 온도, 음악, 절전 방지, 다운로드, 시간대, 자리를 비운 시간.",
            load: "CPU 부하와 열에 땀 흘리기", music: "음악에 맞춰 춤추기",
            rest: "자리를 비우거나 늦은 밤에 졸기", coffee: "절전 방지 중 커피 마시기",
            network: "큰 다운로드 지켜보기", events: "정리를 축하하고 배터리가 부족하면 지치기",
            antics: "가끔 작은 장난",
            hardWork: "CPU 풀가동", overheating: "CPU 과열", cooledDown: "부하가 줄어듦",
            coffeeBreak: "커피 타임", bigDownload: "큰 다운로드", cleanedUp: "공간 확보", justSayingHi: "그냥 인사")
        case .zhHans: return NotchMascotAutomationStrings(
            chip: "芯片", fan: "风扇", cat: "猫咪", ghost: "幽灵", slime: "史莱姆",
            automatic: "自动反应",
            automaticHint: "它会自己对 Mac 正在做的事做出反应：CPU 负载和温度、音乐、保持唤醒、下载、一天中的时间，以及你离开了多久。",
            load: "CPU 负载高、温度高时冒汗", music: "随音乐跳舞",
            rest: "你离开时或深夜打瞌睡", coffee: "保持唤醒时喝咖啡",
            network: "关注大型下载", events: "庆祝清理，电量低时变累",
            antics: "偶尔来点小把戏",
            hardWork: "CPU 全力运转", overheating: "CPU 过热", cooledDown: "负载降下来了",
            coffeeBreak: "咖啡时间", bigDownload: "大型下载", cleanedUp: "空间已释放", justSayingHi: "打个招呼")
        case .zhTW: return NotchMascotAutomationStrings(
            chip: "晶片", fan: "風扇", cat: "貓咪", ghost: "幽靈", slime: "史萊姆",
            automatic: "自動反應",
            automaticHint: "它會自己對 Mac 正在做的事做出反應：CPU 負載和溫度、音樂、保持喚醒、下載、一天中的時段，以及你離開了多久。",
            load: "CPU 負載高、溫度高時冒汗", music: "隨音樂跳舞",
            rest: "你離開時或深夜打瞌睡", coffee: "保持喚醒時喝咖啡",
            network: "留意大型下載", events: "慶祝清理，電量低時變累",
            antics: "偶爾來點小把戲",
            hardWork: "CPU 全力運轉", overheating: "CPU 過熱", cooledDown: "負載降下來了",
            coffeeBreak: "咖啡時間", bigDownload: "大型下載", cleanedUp: "空間已釋放", justSayingHi: "打個招呼")
        case .zhHK: return NotchMascotAutomationStrings(
            chip: "晶片", fan: "風扇", cat: "貓咪", ghost: "幽靈", slime: "史萊姆",
            automatic: "自動反應",
            automaticHint: "它會自己對 Mac 正在做的事作出反應：CPU 負載和溫度、音樂、保持喚醒、下載、一天中的時段，以及你離開了多久。",
            load: "CPU 負載高、溫度高時冒汗", music: "隨音樂跳舞",
            rest: "你離開時或深夜打瞌睡", coffee: "保持喚醒時飲咖啡",
            network: "留意大型下載", events: "慶祝清理，電量低時變攰",
            antics: "間中來點小把戲",
            hardWork: "CPU 全速運轉", overheating: "CPU 過熱", cooledDown: "負載降低了",
            coffeeBreak: "咖啡時間", bigDownload: "大型下載", cleanedUp: "空間已釋放", justSayingHi: "打個招呼")
        case .uk: return NotchMascotAutomationStrings(
            chip: "Чип", fan: "Вентилятор", cat: "Кіт", ghost: "Привид", slime: "Слайм",
            automatic: "Автоматичні реакції",
            automaticHint: "Він сам реагує на те, що робить ваш Mac: навантаження й нагрів CPU, музику, режим «Не давати Mac заснути», завантаження, час доби й те, як довго вас не було.",
            load: "Пітніти від навантаження й нагріву CPU", music: "Танцювати під музику",
            rest: "Засинати, коли вас немає або пізно вночі", coffee: "Пити каву, поки Mac не спить",
            network: "Стежити за великими завантаженнями", events: "Радіти очищенню, втомлюватися при низькому заряді",
            antics: "Іноді трохи пустувати",
            hardWork: "CPU працює на повну", overheating: "CPU перегрівається", cooledDown: "Навантаження спало",
            coffeeBreak: "Кава-брейк", bigDownload: "Велике завантаження", cleanedUp: "Місце звільнено", justSayingHi: "Просто привіт")
        }
    }
}
