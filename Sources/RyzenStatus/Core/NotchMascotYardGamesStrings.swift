// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The yard games under the desktop companion's "Play" menu, and the line
/// each one shows as it starts to say how it is played.
struct NotchMascotYardGamesStrings {
    let fetch: String
    let shells: String
    let moles: String
    let ticTacToe: String
    let simon: String
    let bubbles: String
    let path: String
    let target: String
    let fetchHint: String
    let shellsHint: String
    let molesHint: String
    let ticTacToeHint: String
    let simonHint: String
    let bubblesHint: String
    let pathHint: String
    let targetHint: String
    /// How to stop any of them.
    let stop: String

    func title(_ game: NotchMascotYardGame) -> String {
        switch game {
        case .fetch: return fetch
        case .shells: return shells
        case .moles: return moles
        case .ticTacToe: return ticTacToe
        case .simon: return simon
        case .bubbles: return bubbles
        case .path: return path
        case .target: return target
        }
    }

    func hint(_ game: NotchMascotYardGame) -> String {
        switch game {
        case .fetch: return fetchHint
        case .shells: return shellsHint
        case .moles: return molesHint
        case .ticTacToe: return ticTacToeHint
        case .simon: return simonHint
        case .bubbles: return bubblesHint
        case .path: return pathHint
        case .target: return targetHint
        }
    }
}

extension FeatureStrings {
    // swiftlint:disable:next function_body_length
    static func notchMascotYardGames(_ language: AppLanguage) -> NotchMascotYardGamesStrings {
        switch language {
        case .enUS:
            return .init(fetch: "Fetch", shells: "Shell Game", moles: "Whack-a-Mole", ticTacToe: "Tic-Tac-Toe",
                         simon: "Simon Says", bubbles: "Bubble Pop", path: "Draw a Path", target: "Target Practice",
                         fetchHint: "Grab the ball and throw it", shellsHint: "Watch the coin, then click its cup",
                         molesHint: "Bonk it when it pops up", ticTacToeHint: "You are X: click a square",
                         simonHint: "Watch, then click the pads in the same order",
                         bubblesHint: "Click the bubbles to pop them", pathHint: "Drag to draw a path for it",
                         targetHint: "Click to throw at the target", stop: "Esc to stop")
        case .ptBR:
            return .init(fetch: "Buscar a bolinha", shells: "Jogo dos copos", moles: "Acerte a toupeira",
                         ticTacToe: "Jogo da velha", simon: "Siga a sequência", bubbles: "Estourar bolhas",
                         path: "Desenhar um caminho", target: "Tiro ao alvo",
                         fetchHint: "Pegue a bolinha e jogue", shellsHint: "Olhe a moeda e clique no copo dela",
                         molesHint: "Acerte quando ele aparecer", ticTacToeHint: "Você é o X: clique numa casa",
                         simonHint: "Observe e clique nos blocos na mesma ordem",
                         bubblesHint: "Clique nas bolhas para estourá-las", pathHint: "Arraste para desenhar um caminho",
                         targetHint: "Clique para atirar no alvo", stop: "Esc para parar")
        case .tr:
            return .init(fetch: "Top getir", shells: "Bardak oyunu", moles: "Köstebek vur", ticTacToe: "XOX",
                         simon: "Sırayı takip et", bubbles: "Baloncuk patlat", path: "Yol çiz", target: "Hedef atışı",
                         fetchHint: "Topu tut ve fırlat", shellsHint: "Parayı izle, sonra bardağına tıkla",
                         molesHint: "Ortaya çıkınca ona vur", ticTacToeHint: "Sen X'sin: bir kareye tıkla",
                         simonHint: "İzle, sonra pedlere aynı sırayla tıkla",
                         bubblesHint: "Patlatmak için baloncuklara tıkla", pathHint: "Ona bir yol çizmek için sürükle",
                         targetHint: "Hedefe atmak için tıkla", stop: "Durdurmak için Esc")
        case .ru:
            return .init(fetch: "Апорт", shells: "Напёрстки", moles: "Бей крота", ticTacToe: "Крестики-нолики",
                         simon: "Повтори за мной", bubbles: "Пузыри", path: "Нарисуй путь", target: "Тир",
                         fetchHint: "Схватите мяч и бросьте его",
                         shellsHint: "Следите за монетой и нажмите на её напёрсток",
                         molesHint: "Стукните его, когда он выглянет", ticTacToeHint: "Вы — крестики: нажмите на клетку",
                         simonHint: "Смотрите, затем нажимайте на плитки в том же порядке",
                         bubblesHint: "Нажимайте на пузыри, чтобы лопнуть их",
                         pathHint: "Проведите, чтобы нарисовать ему путь", targetHint: "Нажмите, чтобы бросить в мишень",
                         stop: "Esc — остановить")
        case .es:
            return .init(fetch: "Traer la pelota", shells: "Juego de los vasos", moles: "Golpea al topo",
                         ticTacToe: "Tres en raya", simon: "Simón dice", bubbles: "Explotar burbujas",
                         path: "Dibujar un camino", target: "Tiro al blanco",
                         fetchHint: "Agarra la pelota y lánzala", shellsHint: "Sigue la moneda y haz clic en su vaso",
                         molesHint: "Dale cuando asome", ticTacToeHint: "Eres la X: haz clic en una casilla",
                         simonHint: "Mira y luego pulsa las baldosas en el mismo orden",
                         bubblesHint: "Haz clic en las burbujas para explotarlas",
                         pathHint: "Arrastra para dibujarle un camino", targetHint: "Haz clic para lanzar al blanco",
                         stop: "Esc para parar")
        case .de:
            return .init(fetch: "Apportieren", shells: "Hütchenspiel", moles: "Hau den Maulwurf", ticTacToe: "Tic-Tac-Toe",
                         simon: "Simon sagt", bubbles: "Blasen platzen lassen", path: "Weg zeichnen", target: "Zielwerfen",
                         fetchHint: "Schnapp dir den Ball und wirf ihn",
                         shellsHint: "Folge der Münze und klick ihren Becher an",
                         molesHint: "Hau drauf, wenn er auftaucht", ticTacToeHint: "Du bist X: klick ein Feld an",
                         simonHint: "Schau zu und klick die Felder in derselben Reihenfolge",
                         bubblesHint: "Klick die Blasen an, um sie platzen zu lassen",
                         pathHint: "Zieh, um ihm einen Weg zu zeichnen",
                         targetHint: "Klick, um auf die Zielscheibe zu werfen", stop: "Esc zum Beenden")
        case .fr:
            return .init(fetch: "Rapporte la balle", shells: "Jeu des gobelets", moles: "Tape-taupe", ticTacToe: "Morpion",
                         simon: "Jacques a dit", bubbles: "Bulles à éclater", path: "Dessiner un chemin",
                         target: "Tir sur cible",
                         fetchHint: "Attrapez la balle et lancez-la",
                         shellsHint: "Suivez la pièce, puis cliquez sur son gobelet",
                         molesHint: "Tapez-le quand il sort", ticTacToeHint: "Vous êtes les X : cliquez sur une case",
                         simonHint: "Regardez, puis cliquez sur les dalles dans le même ordre",
                         bubblesHint: "Cliquez sur les bulles pour les éclater",
                         pathHint: "Faites glisser pour lui tracer un chemin",
                         targetHint: "Cliquez pour lancer sur la cible", stop: "Échap pour arrêter")
        case .it:
            return .init(fetch: "Riporta la palla", shells: "Gioco dei bicchieri", moles: "Acchiappa la talpa",
                         ticTacToe: "Tris", simon: "Simon dice", bubbles: "Scoppia le bolle", path: "Disegna un percorso",
                         target: "Tiro al bersaglio",
                         fetchHint: "Afferra la palla e lanciala", shellsHint: "Segui la moneta, poi clicca il suo bicchiere",
                         molesHint: "Colpiscilo quando spunta", ticTacToeHint: "Tu sei la X: clicca una casella",
                         simonHint: "Guarda, poi clicca le piastrelle nello stesso ordine",
                         bubblesHint: "Clicca le bolle per farle scoppiare",
                         pathHint: "Trascina per disegnargli un percorso", targetHint: "Clicca per tirare al bersaglio",
                         stop: "Esc per fermare")
        case .ja:
            return .init(fetch: "とってこい", shells: "カップシャッフル", moles: "モグラたたき", ticTacToe: "三目並べ",
                         simon: "まねっこ", bubbles: "シャボン玉割り", path: "道を描く", target: "的当て",
                         fetchHint: "ボールをつかんで投げよう", shellsHint: "コインを目で追って、そのカップをクリック",
                         molesHint: "顔を出したらたたこう", ticTacToeHint: "あなたは×：マスをクリック",
                         simonHint: "よく見て、同じ順番でパッドをクリック",
                         bubblesHint: "シャボン玉をクリックして割ろう", pathHint: "ドラッグして道を描こう",
                         targetHint: "クリックして的に投げよう", stop: "Escで終了")
        case .ko:
            return .init(fetch: "공 가져오기", shells: "컵 섞기 게임", moles: "두더지 잡기", ticTacToe: "틱택토",
                         simon: "따라 하기", bubbles: "비눗방울 터뜨리기", path: "길 그리기", target: "과녁 맞히기",
                         fetchHint: "공을 잡아서 던지세요", shellsHint: "동전을 잘 보고 그 컵을 클릭하세요",
                         molesHint: "튀어나오면 때리세요", ticTacToeHint: "당신은 X: 칸을 클릭하세요",
                         simonHint: "잘 보고 같은 순서로 패드를 클릭하세요",
                         bubblesHint: "비눗방울을 클릭해 터뜨리세요", pathHint: "드래그해서 길을 그려 주세요",
                         targetHint: "클릭해서 과녁에 던지세요", stop: "Esc로 멈추기")
        case .zhHans:
            return .init(fetch: "捡球", shells: "猜杯子", moles: "打地鼠", ticTacToe: "井字棋",
                         simon: "跟我做", bubbles: "戳泡泡", path: "画条路", target: "打靶",
                         fetchHint: "抓住球扔出去", shellsHint: "盯住硬币，然后点它所在的杯子",
                         molesHint: "它冒头时敲它", ticTacToeHint: "你是 X：点一个格子",
                         simonHint: "看好，然后按同样顺序点地垫",
                         bubblesHint: "点击泡泡把它戳破", pathHint: "拖动为它画一条路",
                         targetHint: "点击向靶子投掷", stop: "按 Esc 停止")
        case .zhTW:
            return .init(fetch: "撿球", shells: "猜杯子", moles: "打地鼠", ticTacToe: "井字遊戲",
                         simon: "跟我做", bubbles: "戳泡泡", path: "畫條路", target: "打靶",
                         fetchHint: "抓住球丟出去", shellsHint: "盯住硬幣，然後點它所在的杯子",
                         molesHint: "它冒頭時敲它", ticTacToeHint: "你是 X：點一個格子",
                         simonHint: "看好，然後依同樣順序點地墊",
                         bubblesHint: "點擊泡泡把它戳破", pathHint: "拖曳為它畫一條路",
                         targetHint: "點擊向靶子投擲", stop: "按 Esc 停止")
        case .zhHK:
            return .init(fetch: "執波", shells: "估杯仔", moles: "打地鼠", ticTacToe: "過三關",
                         simon: "跟住做", bubbles: "篤泡泡", path: "畫條路", target: "掟靶",
                         fetchHint: "捉住個波掟出去", shellsHint: "睇實個銀仔，再撳佢喺嗰個杯",
                         molesHint: "佢一探頭就打佢", ticTacToeHint: "你係 X：撳一格",
                         simonHint: "睇清楚，再跟住同一個次序撳地墊",
                         bubblesHint: "撳泡泡篤爆佢", pathHint: "拖動幫佢畫條路",
                         targetHint: "撳一下掟個靶", stop: "撳 Esc 停")
        case .sk:
            return .init(fetch: "Aport", shells: "Hra s pohármi", moles: "Buchni krtka", ticTacToe: "Piškvorky",
                         simon: "Opakuj po mne", bubbles: "Praskanie bublín", path: "Nakresli cestu",
                         target: "Streľba na terč",
                         fetchHint: "Chyť loptu a hoď ju", shellsHint: "Sleduj mincu a klikni na jej pohár",
                         molesHint: "Buchni ho, keď vykukne", ticTacToeHint: "Si X: klikni na políčko",
                         simonHint: "Pozeraj a potom klikaj na plôšky v rovnakom poradí",
                         bubblesHint: "Klikaj na bubliny, aby praskli", pathHint: "Ťahaj a nakresli mu cestu",
                         targetHint: "Klikni a hoď na terč", stop: "Esc na zastavenie")
        case .uk:
            return .init(fetch: "Апорт", shells: "Наперстки", moles: "Бий крота", ticTacToe: "Хрестики-нулики",
                         simon: "Повторюй за мною", bubbles: "Бульбашки", path: "Намалюй шлях", target: "Тир",
                         fetchHint: "Схопіть м'яч і киньте його",
                         shellsHint: "Стежте за монетою і натисніть на її наперсток",
                         molesHint: "Стукніть його, коли визирне", ticTacToeHint: "Ви — хрестики: натисніть клітинку",
                         simonHint: "Дивіться, а потім натискайте плитки в тому ж порядку",
                         bubblesHint: "Натискайте на бульбашки, щоб лопнути їх",
                         pathHint: "Проведіть, щоб намалювати йому шлях", targetHint: "Натисніть, щоб кинути в мішень",
                         stop: "Esc — зупинити")
        }
    }
}
