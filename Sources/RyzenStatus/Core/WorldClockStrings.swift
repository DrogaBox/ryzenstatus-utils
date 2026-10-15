// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Strings for the world clocks. Same contract as the other FeatureStrings
/// structs: memberwise init with labeled arguments in declaration order, one
/// static per language, all in this file.
struct WorldClockStrings {
    let pageTitle: String
    let hubDescription: String
    let panelDescription: String
    let emptyHint: String
    let addCity: String
    let searchPlaceholder: String
    let noMatches: String
    let remove: String
    let today: String
    let tomorrow: String
    let yesterday: String
    let limitReached: String
    let editClocks: String
}

extension FeatureStrings {
    static func worldClock(_ language: AppLanguage) -> WorldClockStrings {
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

extension WorldClockStrings {
    static let enUS = WorldClockStrings(
        pageTitle: "World clocks",
        hubDescription: "Shows the time in the cities you choose, with the day and the difference from your own.",
        panelDescription: "The time in other cities",
        emptyHint: "No cities yet. Add the ones you follow in Settings.",
        addCity: "Add city",
        searchPlaceholder: "Search a city or time zone",
        noMatches: "No time zone matches.",
        remove: "Remove",
        today: "Today",
        tomorrow: "Tomorrow",
        yesterday: "Yesterday",
        limitReached: "Up to 12 cities.",
        editClocks: "Choose cities"
    )

    static let ptBR = WorldClockStrings(
        pageTitle: "Relógios mundiais",
        hubDescription: "Mostra a hora nas cidades que você escolher, com o dia e a diferença para a sua.",
        panelDescription: "A hora em outras cidades",
        emptyHint: "Nenhuma cidade ainda. Adicione as que você acompanha nos Ajustes.",
        addCity: "Adicionar cidade",
        searchPlaceholder: "Buscar cidade ou fuso horário",
        noMatches: "Nenhum fuso horário corresponde.",
        remove: "Remover",
        today: "Hoje",
        tomorrow: "Amanhã",
        yesterday: "Ontem",
        limitReached: "Até 12 cidades.",
        editClocks: "Escolher cidades"
    )

    static let tr = WorldClockStrings(
        pageTitle: "Dünya saatleri",
        hubDescription: "Seçtiğiniz şehirlerdeki saati, günü ve sizinkiyle farkı ile gösterir.",
        panelDescription: "Diğer şehirlerde saat",
        emptyHint: "Henüz şehir yok. Takip ettiklerinizi Ayarlar'dan ekleyin.",
        addCity: "Şehir ekle",
        searchPlaceholder: "Şehir veya saat dilimi ara",
        noMatches: "Eşleşen saat dilimi yok.",
        remove: "Kaldır",
        today: "Bugün",
        tomorrow: "Yarın",
        yesterday: "Dün",
        limitReached: "En fazla 12 şehir.",
        editClocks: "Şehirleri seç"
    )

    static let ru = WorldClockStrings(
        pageTitle: "Мировое время",
        hubDescription: "Показывает время в выбранных городах, день и разницу с вашим временем.",
        panelDescription: "Время в других городах",
        emptyHint: "Городов пока нет. Добавьте нужные в Настройках.",
        addCity: "Добавить город",
        searchPlaceholder: "Поиск города или часового пояса",
        noMatches: "Подходящих часовых поясов нет.",
        remove: "Удалить",
        today: "Сегодня",
        tomorrow: "Завтра",
        yesterday: "Вчера",
        limitReached: "Не более 12 городов.",
        editClocks: "Выбрать города"
    )

    static let es = WorldClockStrings(
        pageTitle: "Relojes del mundo",
        hubDescription: "Muestra la hora en las ciudades que elijas, con el día y la diferencia con la tuya.",
        panelDescription: "La hora en otras ciudades",
        emptyHint: "Aún no hay ciudades. Añade las que sigues en Ajustes.",
        addCity: "Añadir ciudad",
        searchPlaceholder: "Buscar ciudad o zona horaria",
        noMatches: "Ninguna zona horaria coincide.",
        remove: "Quitar",
        today: "Hoy",
        tomorrow: "Mañana",
        yesterday: "Ayer",
        limitReached: "Hasta 12 ciudades.",
        editClocks: "Elegir ciudades"
    )

    static let sk = WorldClockStrings(
        pageTitle: "Svetový čas",
        hubDescription: "Zobrazuje čas vo vybraných mestách spolu s dňom a rozdielom oproti vášmu.",
        panelDescription: "Čas v iných mestách",
        emptyHint: "Zatiaľ žiadne mestá. Pridajte tie, ktoré sledujete, v Nastaveniach.",
        addCity: "Pridať mesto",
        searchPlaceholder: "Hľadať mesto alebo časové pásmo",
        noMatches: "Žiadne časové pásmo nezodpovedá.",
        remove: "Odstrániť",
        today: "Dnes",
        tomorrow: "Zajtra",
        yesterday: "Včera",
        limitReached: "Najviac 12 miest.",
        editClocks: "Vybrať mestá"
    )

    static let de = WorldClockStrings(
        pageTitle: "Weltuhren",
        hubDescription: "Zeigt die Uhrzeit in den gewählten Städten, mit Tag und Abstand zu deiner Zeit.",
        panelDescription: "Die Uhrzeit in anderen Städten",
        emptyHint: "Noch keine Städte. Füge die gewünschten in den Einstellungen hinzu.",
        addCity: "Stadt hinzufügen",
        searchPlaceholder: "Stadt oder Zeitzone suchen",
        noMatches: "Keine passende Zeitzone.",
        remove: "Entfernen",
        today: "Heute",
        tomorrow: "Morgen",
        yesterday: "Gestern",
        limitReached: "Bis zu 12 Städte.",
        editClocks: "Städte wählen"
    )

    static let fr = WorldClockStrings(
        pageTitle: "Horloges mondiales",
        hubDescription: "Affiche l’heure des villes choisies, avec le jour et le décalage par rapport à la vôtre.",
        panelDescription: "L’heure dans d’autres villes",
        emptyHint: "Aucune ville pour l’instant. Ajoutez celles que vous suivez dans les Réglages.",
        addCity: "Ajouter une ville",
        searchPlaceholder: "Rechercher une ville ou un fuseau",
        noMatches: "Aucun fuseau horaire ne correspond.",
        remove: "Retirer",
        today: "Aujourd’hui",
        tomorrow: "Demain",
        yesterday: "Hier",
        limitReached: "Jusqu’à 12 villes.",
        editClocks: "Choisir les villes"
    )

    static let it = WorldClockStrings(
        pageTitle: "Orologi del mondo",
        hubDescription: "Mostra l’ora nelle città scelte, con il giorno e la differenza rispetto alla tua.",
        panelDescription: "L’ora in altre città",
        emptyHint: "Ancora nessuna città. Aggiungi quelle che segui nelle Impostazioni.",
        addCity: "Aggiungi città",
        searchPlaceholder: "Cerca città o fuso orario",
        noMatches: "Nessun fuso orario corrisponde.",
        remove: "Rimuovi",
        today: "Oggi",
        tomorrow: "Domani",
        yesterday: "Ieri",
        limitReached: "Fino a 12 città.",
        editClocks: "Scegli città"
    )

    static let ja = WorldClockStrings(
        pageTitle: "世界時計",
        hubDescription: "選んだ都市の時刻を、日付と現在地との時差とともに表示します。",
        panelDescription: "ほかの都市の時刻",
        emptyHint: "都市がまだありません。設定で追加してください。",
        addCity: "都市を追加",
        searchPlaceholder: "都市またはタイムゾーンを検索",
        noMatches: "一致するタイムゾーンがありません。",
        remove: "削除",
        today: "今日",
        tomorrow: "明日",
        yesterday: "昨日",
        limitReached: "最大12都市までです。",
        editClocks: "都市を選択"
    )

    static let ko = WorldClockStrings(
        pageTitle: "세계 시계",
        hubDescription: "선택한 도시의 시간을 날짜와 현재 위치와의 시차와 함께 보여 줍니다.",
        panelDescription: "다른 도시의 시간",
        emptyHint: "아직 도시가 없습니다. 설정에서 추가하세요.",
        addCity: "도시 추가",
        searchPlaceholder: "도시 또는 시간대 검색",
        noMatches: "일치하는 시간대가 없습니다.",
        remove: "제거",
        today: "오늘",
        tomorrow: "내일",
        yesterday: "어제",
        limitReached: "최대 12개 도시까지.",
        editClocks: "도시 선택"
    )

    static let zhHans = WorldClockStrings(
        pageTitle: "世界时钟",
        hubDescription: "显示所选城市的时间，以及日期和与你所在地的时差。",
        panelDescription: "其他城市的时间",
        emptyHint: "还没有城市。请在设置中添加。",
        addCity: "添加城市",
        searchPlaceholder: "搜索城市或时区",
        noMatches: "没有匹配的时区。",
        remove: "移除",
        today: "今天",
        tomorrow: "明天",
        yesterday: "昨天",
        limitReached: "最多 12 个城市。",
        editClocks: "选择城市"
    )

    static let zhTW = WorldClockStrings(
        pageTitle: "世界時鐘",
        hubDescription: "顯示所選城市的時間，以及日期和與你所在地的時差。",
        panelDescription: "其他城市的時間",
        emptyHint: "尚未加入城市。請在設定中加入。",
        addCity: "加入城市",
        searchPlaceholder: "搜尋城市或時區",
        noMatches: "沒有相符的時區。",
        remove: "移除",
        today: "今天",
        tomorrow: "明天",
        yesterday: "昨天",
        limitReached: "最多 12 個城市。",
        editClocks: "選擇城市"
    )

    static let zhHK = WorldClockStrings(
        pageTitle: "世界時鐘",
        hubDescription: "顯示所選城市的時間，以及日期和與你所在地的時差。",
        panelDescription: "其他城市的時間",
        emptyHint: "尚未加入城市。請在設定中加入。",
        addCity: "加入城市",
        searchPlaceholder: "搜尋城市或時區",
        noMatches: "沒有相符的時區。",
        remove: "移除",
        today: "今日",
        tomorrow: "明日",
        yesterday: "昨日",
        limitReached: "最多 12 個城市。",
        editClocks: "選擇城市"
    )

    static let uk = WorldClockStrings(
        pageTitle: "Світовий час",
        hubDescription: "Показує час у вибраних містах разом із днем і різницею з вашим часом.",
        panelDescription: "Час в інших містах",
        emptyHint: "Міст ще немає. Додайте потрібні в Параметрах.",
        addCity: "Додати місто",
        searchPlaceholder: "Пошук міста або часового поясу",
        noMatches: "Відповідних часових поясів немає.",
        remove: "Вилучити",
        today: "Сьогодні",
        tomorrow: "Завтра",
        yesterday: "Учора",
        limitReached: "Не більше 12 міст.",
        editClocks: "Вибрати міста"
    )
}
