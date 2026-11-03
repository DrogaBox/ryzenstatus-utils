// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The companion's alarm clocks: the sign it holds up to set them, the one
/// it rings with, its menu's entries, the row in Settings, the tunes it
/// plays and the siren that sends the guests home.
struct NotchMascotAlarmStrings {
    let alarm: String
    let alarms: String
    /// The companion's menu item that opens its sign of alarms.
    let alarmsMenu: String
    /// The menu item that sends every guest home at once.
    let everyoneHome: String
    /// Shouted on the sign the siren flashes over, in capitals.
    let everyoneHomeSign: String
    let noAlarms: String
    let noAlarmsHint: String
    let addAlarm: String
    let editAlarm: String
    let time: String
    let repeatTitle: String
    let once: String
    let everyDay: String
    let weekdays: String
    let weekend: String
    let label: String
    let sound: String
    /// The three groups of sounds: the app's tunes, the Mac's and those added.
    let tunes: String
    let system: String
    let yours: String
    let addSound: String
    let removeSound: String
    let cannotPlay: String
    let snooze: String
    /// A number of minutes; `%d` is the number.
    let minutes: String
    let stop: String
    let delete: String
    let cancel: String
    let save: String
    let tryIt: String
    /// What the keys do while it rings.
    let keysHint: String
    /// The ringing, as a comic letters it.
    let ring: String
    let settingsCaption: String
    let openSign: String
    let sunrise: String
    let marimba: String
    let cuckoo: String
    let bell: String
    let arcade: String
    let siren: String

    func tone(_ tone: NotchMascotAlarmTone) -> String {
        switch tone {
        case .sunrise: return sunrise
        case .marimba: return marimba
        case .cuckoo: return cuckoo
        case .bell: return bell
        case .chiptune: return arcade
        case .siren: return siren
        }
    }

    func minutes(_ count: Int) -> String { String(format: minutes, count) }

    /// "Snooze 9 min".
    func snoozeButton(_ count: Int) -> String { snooze + " · " + minutes(count) }

    /// `alarm`'s time as the clock in `language` writes it.
    func time(_ alarm: NotchMascotAlarm, calendar: Calendar, language: AppLanguage = L10n.shared.language) -> String {
        var parts = DateComponents()
        parts.hour = alarm.hour
        parts.minute = alarm.minute
        let date = calendar.date(from: parts) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.rawValue)
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: date)
    }

    /// The days an alarm rings on, in a few words.
    func days(_ days: Set<Int>, language: AppLanguage = L10n.shared.language) -> String {
        if days.isEmpty { return once }
        if days == NotchMascotAlarmSchedule.everyDay { return everyDay }
        if days == NotchMascotAlarmSchedule.weekdays { return weekdays }
        if days == NotchMascotAlarmSchedule.weekend { return weekend }
        let names = Self.weekdayNames(language, short: true)
        return NotchMascotAlarmSchedule.weekOrder(Calendar.autoupdatingCurrent).filter(days.contains)
            .map { names[$0 - 1] }.joined(separator: " ")
    }

    /// The weekdays' names in `language`, Sunday first: a letter or two, or short.
    static func weekdayNames(_ language: AppLanguage, short: Bool) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: language.rawValue)
        return short ? calendar.shortStandaloneWeekdaySymbols : calendar.veryShortStandaloneWeekdaySymbols
    }
}

extension FeatureStrings {
    static func notchMascotAlarms(_ language: AppLanguage) -> NotchMascotAlarmStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .sk: return .sk
        case .uk: return .uk
        }
    }
}

extension NotchMascotAlarmStrings {
    static let enUS = NotchMascotAlarmStrings(
        alarm: "Alarm", alarms: "Alarms", alarmsMenu: "Alarms…", everyoneHome: "Everyone Home!",
        everyoneHomeSign: "EVERYONE HOME!", noAlarms: "No alarms yet", noAlarmsHint: "Add one and I’ll wake you up.",
        addAlarm: "Add Alarm", editAlarm: "Edit Alarm", time: "Time", repeatTitle: "Repeat", once: "Once",
        everyDay: "Every day", weekdays: "Weekdays", weekend: "Weekends", label: "Label", sound: "Sound",
        tunes: "Tunes", system: "System", yours: "Yours", addSound: "Add Sound…", removeSound: "Remove Sound",
        cannotPlay: "That file can’t be played.", snooze: "Snooze", minutes: "%d min", stop: "Stop", delete: "Delete",
        cancel: "Cancel", save: "Save", tryIt: "Try It", keysHint: "Space: stop · S: snooze", ring: "RIIING!",
        settingsCaption: "Wake-up alarms, every day or on the days you pick. Your companion rings them holding up a sign.",
        openSign: "Open Sign", sunrise: "Sunrise", marimba: "Marimba", cuckoo: "Cuckoo", bell: "Old Bell",
        arcade: "Arcade", siren: "Siren")

    static let ptBR = NotchMascotAlarmStrings(
        alarm: "Alarme", alarms: "Alarmes", alarmsMenu: "Alarmes…", everyoneHome: "Todo mundo para casa!",
        everyoneHomeSign: "TODO MUNDO PARA CASA!", noAlarms: "Nenhum alarme ainda",
        noAlarmsHint: "Crie um e eu te acordo.", addAlarm: "Adicionar alarme", editAlarm: "Editar alarme",
        time: "Hora", repeatTitle: "Repetir", once: "Uma vez", everyDay: "Todos os dias", weekdays: "Dias úteis",
        weekend: "Fins de semana", label: "Nome", sound: "Som", tunes: "Melodias", system: "Sistema", yours: "Seus",
        addSound: "Adicionar som…", removeSound: "Remover som", cannotPlay: "Esse arquivo não pode ser tocado.",
        snooze: "Soneca", minutes: "%d min", stop: "Parar", delete: "Apagar", cancel: "Cancelar", save: "Salvar",
        tryIt: "Testar", keysHint: "Espaço: parar · S: soneca", ring: "TRIIIM!",
        settingsCaption: "Alarmes para acordar, todos os dias ou nos dias que você escolher. Seu companheiro toca segurando uma placa.",
        openSign: "Abrir placa", sunrise: "Amanhecer", marimba: "Marimba", cuckoo: "Cuco", bell: "Sino antigo",
        arcade: "Fliperama", siren: "Sirene")

    static let tr = NotchMascotAlarmStrings(
        alarm: "Alarm", alarms: "Alarmlar", alarmsMenu: "Alarmlar…", everyoneHome: "Herkes evine!",
        everyoneHomeSign: "HERKES EVİNE!", noAlarms: "Henüz alarm yok", noAlarmsHint: "Bir tane ekle, seni ben uyandırırım.",
        addAlarm: "Alarm ekle", editAlarm: "Alarmı düzenle", time: "Saat", repeatTitle: "Tekrar", once: "Bir kez",
        everyDay: "Her gün", weekdays: "Hafta içi", weekend: "Hafta sonu", label: "Etiket", sound: "Ses",
        tunes: "Melodiler", system: "Sistem", yours: "Seninkiler", addSound: "Ses ekle…", removeSound: "Sesi kaldır",
        cannotPlay: "Bu dosya çalınamıyor.", snooze: "Ertele", minutes: "%d dk", stop: "Durdur", delete: "Sil",
        cancel: "Vazgeç", save: "Kaydet", tryIt: "Dene", keysHint: "Boşluk: durdur · S: ertele", ring: "ZIRRR!",
        settingsCaption: "Her gün ya da seçtiğin günlerde uyandıran alarmlar. Arkadaşın onları bir tabela tutarak çalar.",
        openSign: "Tabelayı aç", sunrise: "Gün doğumu", marimba: "Marimba", cuckoo: "Guguk", bell: "Eski zil",
        arcade: "Atari", siren: "Siren")

    static let ru = NotchMascotAlarmStrings(
        alarm: "Будильник", alarms: "Будильники", alarmsMenu: "Будильники…", everyoneHome: "Все по домам!",
        everyoneHomeSign: "ВСЕ ПО ДОМАМ!", noAlarms: "Будильников пока нет", noAlarmsHint: "Добавьте один — и я вас разбужу.",
        addAlarm: "Добавить будильник", editAlarm: "Изменить будильник", time: "Время", repeatTitle: "Повтор",
        once: "Один раз", everyDay: "Каждый день", weekdays: "По будням", weekend: "По выходным", label: "Название",
        sound: "Звук", tunes: "Мелодии", system: "Системные", yours: "Ваши", addSound: "Добавить звук…",
        removeSound: "Удалить звук", cannotPlay: "Этот файл нельзя воспроизвести.", snooze: "Отложить",
        minutes: "%d мин", stop: "Стоп", delete: "Удалить", cancel: "Отмена", save: "Сохранить", tryIt: "Проверить",
        keysHint: "Пробел: стоп · S: отложить", ring: "ДЗЫНЬ!",
        settingsCaption: "Будильники на каждый день или на выбранные дни. Ваш компаньон звонит, держа табличку.",
        openSign: "Открыть табличку", sunrise: "Рассвет", marimba: "Маримба", cuckoo: "Кукушка",
        bell: "Старый звонок", arcade: "Аркада", siren: "Сирена")

    static let es = NotchMascotAlarmStrings(
        alarm: "Alarma", alarms: "Alarmas", alarmsMenu: "Alarmas…", everyoneHome: "¡Todos a casa!",
        everyoneHomeSign: "¡TODOS A CASA!", noAlarms: "Todavía no hay alarmas", noAlarmsHint: "Agregá una y te despierto.",
        addAlarm: "Agregar alarma", editAlarm: "Editar alarma", time: "Hora", repeatTitle: "Repetir", once: "Una vez",
        everyDay: "Todos los días", weekdays: "Días de semana", weekend: "Fines de semana", label: "Nombre",
        sound: "Sonido", tunes: "Melodías", system: "Sistema", yours: "Tuyos", addSound: "Agregar sonido…",
        removeSound: "Quitar sonido", cannotPlay: "Ese archivo no se puede reproducir.", snooze: "Posponer",
        minutes: "%d min", stop: "Detener", delete: "Borrar", cancel: "Cancelar", save: "Guardar", tryIt: "Probar",
        keysHint: "Espacio: detener · S: posponer", ring: "¡RIIING!",
        settingsCaption: "Alarmas para despertarte, todos los días o los días que elijas. Tu compañero las hace sonar sosteniendo un cartel.",
        openSign: "Abrir cartel", sunrise: "Amanecer", marimba: "Marimba", cuckoo: "Cucú", bell: "Campana antigua",
        arcade: "Arcade", siren: "Sirena")

    static let de = NotchMascotAlarmStrings(
        alarm: "Wecker", alarms: "Wecker", alarmsMenu: "Wecker…", everyoneHome: "Alle nach Hause!",
        everyoneHomeSign: "ALLE NACH HAUSE!", noAlarms: "Noch keine Wecker", noAlarmsHint: "Stell einen ein, ich wecke dich.",
        addAlarm: "Wecker hinzufügen", editAlarm: "Wecker bearbeiten", time: "Uhrzeit", repeatTitle: "Wiederholen",
        once: "Einmal", everyDay: "Täglich", weekdays: "Werktags", weekend: "Am Wochenende", label: "Name",
        sound: "Ton", tunes: "Melodien", system: "System", yours: "Deine", addSound: "Ton hinzufügen…",
        removeSound: "Ton entfernen", cannotPlay: "Diese Datei lässt sich nicht abspielen.", snooze: "Schlummern",
        minutes: "%d Min.", stop: "Stopp", delete: "Löschen", cancel: "Abbrechen", save: "Sichern", tryIt: "Testen",
        keysHint: "Leertaste: Stopp · S: Schlummern", ring: "RIIING!",
        settingsCaption: "Wecker für jeden Tag oder für die Tage deiner Wahl. Dein Begleiter klingelt mit einem Schild in den Händen.",
        openSign: "Schild öffnen", sunrise: "Sonnenaufgang", marimba: "Marimba", cuckoo: "Kuckuck",
        bell: "Alte Glocke", arcade: "Arcade", siren: "Sirene")

    static let fr = NotchMascotAlarmStrings(
        alarm: "Alarme", alarms: "Alarmes", alarmsMenu: "Alarmes…", everyoneHome: "Tout le monde à la maison !",
        everyoneHomeSign: "TOUT LE MONDE À LA MAISON !", noAlarms: "Aucune alarme pour l’instant",
        noAlarmsHint: "Ajoutez-en une et je vous réveille.", addAlarm: "Ajouter une alarme", editAlarm: "Modifier l’alarme",
        time: "Heure", repeatTitle: "Répéter", once: "Une fois", everyDay: "Tous les jours", weekdays: "En semaine",
        weekend: "Le week-end", label: "Nom", sound: "Son", tunes: "Mélodies", system: "Système", yours: "Les vôtres",
        addSound: "Ajouter un son…", removeSound: "Retirer le son", cannotPlay: "Ce fichier ne peut pas être lu.",
        snooze: "Répéter plus tard", minutes: "%d min", stop: "Arrêter", delete: "Supprimer", cancel: "Annuler",
        save: "Enregistrer", tryIt: "Essayer", keysHint: "Espace : arrêter · S : plus tard", ring: "DRIIING !",
        settingsCaption: "Des alarmes pour vous réveiller, chaque jour ou les jours choisis. Votre compagnon les sonne en brandissant une pancarte.",
        openSign: "Ouvrir la pancarte", sunrise: "Lever du soleil", marimba: "Marimba", cuckoo: "Coucou",
        bell: "Vieille cloche", arcade: "Arcade", siren: "Sirène")

    static let it = NotchMascotAlarmStrings(
        alarm: "Sveglia", alarms: "Sveglie", alarmsMenu: "Sveglie…", everyoneHome: "Tutti a casa!",
        everyoneHomeSign: "TUTTI A CASA!", noAlarms: "Ancora nessuna sveglia", noAlarmsHint: "Aggiungine una e ti sveglio io.",
        addAlarm: "Aggiungi sveglia", editAlarm: "Modifica sveglia", time: "Ora", repeatTitle: "Ripeti", once: "Una volta",
        everyDay: "Ogni giorno", weekdays: "Giorni feriali", weekend: "Fine settimana", label: "Nome", sound: "Suono",
        tunes: "Melodie", system: "Sistema", yours: "Tuoi", addSound: "Aggiungi suono…", removeSound: "Rimuovi suono",
        cannotPlay: "Questo file non si può riprodurre.", snooze: "Posticipa", minutes: "%d min", stop: "Ferma",
        delete: "Elimina", cancel: "Annulla", save: "Salva", tryIt: "Prova", keysHint: "Spazio: ferma · S: posticipa",
        ring: "DRIIIN!",
        settingsCaption: "Sveglie per ogni giorno o per i giorni che scegli. Il tuo compagno le suona tenendo in alto un cartello.",
        openSign: "Apri cartello", sunrise: "Alba", marimba: "Marimba", cuckoo: "Cucù", bell: "Vecchia campana",
        arcade: "Arcade", siren: "Sirena")

    static let ja = NotchMascotAlarmStrings(
        alarm: "アラーム", alarms: "アラーム", alarmsMenu: "アラーム…", everyoneHome: "みんな帰って！",
        everyoneHomeSign: "みんな帰って！", noAlarms: "アラームはまだありません", noAlarmsHint: "追加してくれたら起こしてあげる。",
        addAlarm: "アラームを追加", editAlarm: "アラームを編集", time: "時刻", repeatTitle: "繰り返し", once: "1回のみ",
        everyDay: "毎日", weekdays: "平日", weekend: "週末", label: "ラベル", sound: "サウンド", tunes: "メロディ",
        system: "システム", yours: "追加したもの", addSound: "サウンドを追加…", removeSound: "サウンドを削除",
        cannotPlay: "このファイルは再生できません。", snooze: "スヌーズ", minutes: "%d分", stop: "停止", delete: "削除",
        cancel: "キャンセル", save: "保存", tryIt: "試す", keysHint: "スペース：停止 · S：スヌーズ", ring: "ジリリリ！",
        settingsCaption: "毎日、または選んだ曜日に鳴る目覚ましアラーム。コンパニオンが看板を掲げて鳴らします。",
        openSign: "看板を開く", sunrise: "日の出", marimba: "マリンバ", cuckoo: "カッコウ", bell: "古いベル",
        arcade: "アーケード", siren: "サイレン")

    static let ko = NotchMascotAlarmStrings(
        alarm: "알람", alarms: "알람", alarmsMenu: "알람…", everyoneHome: "모두 집으로!",
        everyoneHomeSign: "모두 집으로!", noAlarms: "아직 알람이 없어요", noAlarmsHint: "하나 추가하면 내가 깨워 줄게요.",
        addAlarm: "알람 추가", editAlarm: "알람 편집", time: "시간", repeatTitle: "반복", once: "한 번",
        everyDay: "매일", weekdays: "평일", weekend: "주말", label: "레이블", sound: "사운드", tunes: "멜로디",
        system: "시스템", yours: "추가한 소리", addSound: "사운드 추가…", removeSound: "사운드 삭제",
        cannotPlay: "이 파일은 재생할 수 없어요.", snooze: "다시 알림", minutes: "%d분", stop: "중단", delete: "삭제",
        cancel: "취소", save: "저장", tryIt: "들어 보기", keysHint: "스페이스: 중단 · S: 다시 알림", ring: "따르릉!",
        settingsCaption: "매일 또는 고른 요일에 깨워 주는 알람. 컴패니언이 팻말을 들고 울려 줘요.",
        openSign: "팻말 열기", sunrise: "해돋이", marimba: "마림바", cuckoo: "뻐꾸기", bell: "옛날 종",
        arcade: "아케이드", siren: "사이렌")

    static let zhHans = NotchMascotAlarmStrings(
        alarm: "闹钟", alarms: "闹钟", alarmsMenu: "闹钟…", everyoneHome: "大家都回家！",
        everyoneHomeSign: "大家都回家！", noAlarms: "还没有闹钟", noAlarmsHint: "添加一个，我来叫醒你。",
        addAlarm: "添加闹钟", editAlarm: "编辑闹钟", time: "时间", repeatTitle: "重复", once: "仅一次",
        everyDay: "每天", weekdays: "工作日", weekend: "周末", label: "标签", sound: "铃声", tunes: "旋律",
        system: "系统", yours: "你添加的", addSound: "添加铃声…", removeSound: "移除铃声",
        cannotPlay: "这个文件无法播放。", snooze: "稍后提醒", minutes: "%d 分钟", stop: "停止", delete: "删除",
        cancel: "取消", save: "存储", tryIt: "试听", keysHint: "空格：停止 · S：稍后提醒", ring: "叮铃铃！",
        settingsCaption: "每天或在你选的日子叫醒你的闹钟。你的伙伴会举着牌子响铃。",
        openSign: "打开牌子", sunrise: "日出", marimba: "马林巴", cuckoo: "布谷鸟", bell: "老式铃铛",
        arcade: "街机", siren: "警笛")

    static let zhTW = NotchMascotAlarmStrings(
        alarm: "鬧鐘", alarms: "鬧鐘", alarmsMenu: "鬧鐘…", everyoneHome: "大家都回家！",
        everyoneHomeSign: "大家都回家！", noAlarms: "還沒有鬧鐘", noAlarmsHint: "加一個，我來叫醒你。",
        addAlarm: "加入鬧鐘", editAlarm: "編輯鬧鐘", time: "時間", repeatTitle: "重複", once: "僅一次",
        everyDay: "每天", weekdays: "平日", weekend: "週末", label: "標籤", sound: "提示聲", tunes: "旋律",
        system: "系統", yours: "你加入的", addSound: "加入提示聲…", removeSound: "移除提示聲",
        cannotPlay: "這個檔案無法播放。", snooze: "稍後提醒", minutes: "%d 分鐘", stop: "停止", delete: "刪除",
        cancel: "取消", save: "儲存", tryIt: "試聽", keysHint: "空白鍵：停止 · S：稍後提醒", ring: "叮鈴鈴！",
        settingsCaption: "每天或在你選的日子叫醒你的鬧鐘。你的夥伴會舉著牌子響鈴。",
        openSign: "打開牌子", sunrise: "日出", marimba: "馬林巴", cuckoo: "布穀鳥", bell: "老式鈴鐺",
        arcade: "街機", siren: "警笛")

    static let zhHK = NotchMascotAlarmStrings(
        alarm: "鬧鐘", alarms: "鬧鐘", alarmsMenu: "鬧鐘…", everyoneHome: "大家返屋企！",
        everyoneHomeSign: "大家返屋企！", noAlarms: "仲未有鬧鐘", noAlarmsHint: "加一個，我嚟叫醒你。",
        addAlarm: "加入鬧鐘", editAlarm: "編輯鬧鐘", time: "時間", repeatTitle: "重複", once: "一次",
        everyDay: "每日", weekdays: "平日", weekend: "週末", label: "標籤", sound: "提示聲", tunes: "旋律",
        system: "系統", yours: "你加入嘅", addSound: "加入提示聲…", removeSound: "移除提示聲",
        cannotPlay: "呢個檔案播唔到。", snooze: "稍後提醒", minutes: "%d 分鐘", stop: "停止", delete: "刪除",
        cancel: "取消", save: "儲存", tryIt: "試聽", keysHint: "空白鍵：停止 · S：稍後提醒", ring: "叮鈴鈴！",
        settingsCaption: "每日或者喺你揀嘅日子叫醒你嘅鬧鐘。你嘅夥伴會舉住牌響鈴。",
        openSign: "打開牌", sunrise: "日出", marimba: "馬林巴", cuckoo: "布穀鳥", bell: "舊式鈴",
        arcade: "街機", siren: "警笛")

    static let sk = NotchMascotAlarmStrings(
        alarm: "Budík", alarms: "Budíky", alarmsMenu: "Budíky…", everyoneHome: "Všetci domov!",
        everyoneHomeSign: "VŠETCI DOMOV!", noAlarms: "Zatiaľ žiadne budíky", noAlarmsHint: "Pridaj jeden a ja ťa zobudím.",
        addAlarm: "Pridať budík", editAlarm: "Upraviť budík", time: "Čas", repeatTitle: "Opakovať", once: "Raz",
        everyDay: "Každý deň", weekdays: "Pracovné dni", weekend: "Víkendy", label: "Názov", sound: "Zvuk",
        tunes: "Melódie", system: "Systém", yours: "Tvoje", addSound: "Pridať zvuk…", removeSound: "Odstrániť zvuk",
        cannotPlay: "Tento súbor sa nedá prehrať.", snooze: "Odložiť", minutes: "%d min", stop: "Zastaviť",
        delete: "Vymazať", cancel: "Zrušiť", save: "Uložiť", tryIt: "Vyskúšať", keysHint: "Medzerník: zastaviť · S: odložiť",
        ring: "CRRRN!",
        settingsCaption: "Budíky na každý deň alebo na dni, ktoré vyberieš. Tvoj spoločník zvoní s tabuľou v rukách.",
        openSign: "Otvoriť tabuľu", sunrise: "Východ slnka", marimba: "Marimba", cuckoo: "Kukučka",
        bell: "Starý zvonec", arcade: "Arkáda", siren: "Siréna")

    static let uk = NotchMascotAlarmStrings(
        alarm: "Будильник", alarms: "Будильники", alarmsMenu: "Будильники…", everyoneHome: "Усі по домівках!",
        everyoneHomeSign: "УСІ ПО ДОМІВКАХ!", noAlarms: "Будильників ще немає", noAlarmsHint: "Додайте один — і я вас розбуджу.",
        addAlarm: "Додати будильник", editAlarm: "Змінити будильник", time: "Час", repeatTitle: "Повтор",
        once: "Один раз", everyDay: "Щодня", weekdays: "У будні", weekend: "У вихідні", label: "Назва", sound: "Звук",
        tunes: "Мелодії", system: "Системні", yours: "Ваші", addSound: "Додати звук…", removeSound: "Видалити звук",
        cannotPlay: "Цей файл не можна відтворити.", snooze: "Відкласти", minutes: "%d хв", stop: "Стоп",
        delete: "Видалити", cancel: "Скасувати", save: "Зберегти", tryIt: "Перевірити",
        keysHint: "Пробіл: стоп · S: відкласти", ring: "ДЗЕЛЕНЬ!",
        settingsCaption: "Будильники на щодень або на обрані дні. Ваш компаньйон дзвонить, тримаючи табличку.",
        openSign: "Відкрити табличку", sunrise: "Світанок", marimba: "Маримба", cuckoo: "Зозуля",
        bell: "Старий дзвоник", arcade: "Аркада", siren: "Сирена")
}
