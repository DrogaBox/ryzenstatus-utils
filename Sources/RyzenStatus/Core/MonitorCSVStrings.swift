// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Settings › Monitor: the continuous CSV log and the history export.
struct MonitorCSVFeatureStrings {
    let section: String
    let logTitle: String
    let logButton: String
    let logCaption: String
    let stop: String
    /// "%@" is the formatted row count.
    let rowsWritten: String
    let exportTitle: String
    let exportButton: String
    let exportCaption: String
    let rangeLabel: String
    let logFailedTitle: String
    let exportFailedTitle: String
    /// "%@" is the file name.
    let writeFailedBody: String
}

extension FeatureStrings {
    static func monitorCSV(_ language: AppLanguage) -> MonitorCSVFeatureStrings {
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

extension MonitorCSVFeatureStrings {
    static let enUS = MonitorCSVFeatureStrings(
        section: "Logging",
        logTitle: "CSV log",
        logButton: "Log to CSV…",
        logCaption: "Writes a row every second with CPU load, temperature, package power, average clock and EPP, GPU temperature and power, and each fan's speed. Logging stops when RyzenStatus quits.",
        stop: "Stop",
        rowsWritten: "Rows written: %@",
        exportTitle: "History",
        exportButton: "Export history…",
        exportCaption: "Saves the long history as CSV, one column per reading. Up to an hour comes in 5-second steps, longer ranges in 1-minute steps.",
        rangeLabel: "Range",
        logFailedTitle: "CSV logging stopped",
        exportFailedTitle: "History export failed",
        writeFailedBody: "RyzenStatus could not write to “%@”."
    )

    static let ptBR = MonitorCSVFeatureStrings(
        section: "Registro",
        logTitle: "Registro CSV",
        logButton: "Registrar em CSV…",
        logCaption: "Grava uma linha por segundo com uso da CPU, temperatura, potência do pacote, clock médio e EPP, temperatura e potência da GPU e a velocidade de cada ventoinha. O registro para quando o RyzenStatus é encerrado.",
        stop: "Parar",
        rowsWritten: "Linhas gravadas: %@",
        exportTitle: "Histórico",
        exportButton: "Exportar Histórico…",
        exportCaption: "Salva o histórico longo em CSV, uma coluna por leitura. Até uma hora vem em passos de 5 segundos; intervalos maiores, em passos de 1 minuto.",
        rangeLabel: "Intervalo",
        logFailedTitle: "Registro CSV interrompido",
        exportFailedTitle: "Falha ao exportar o histórico",
        writeFailedBody: "O RyzenStatus não conseguiu gravar em “%@”."
    )

    static let tr = MonitorCSVFeatureStrings(
        section: "Kayıt",
        logTitle: "CSV kaydı",
        logButton: "CSV'ye Kaydet…",
        logCaption: "Her saniye CPU yükü, sıcaklık, paket gücü, ortalama saat hızı ve EPP, GPU sıcaklığı ve gücü ile her fanın hızını içeren bir satır yazar. RyzenStatus kapanınca kayıt durur.",
        stop: "Durdur",
        rowsWritten: "Yazılan satır: %@",
        exportTitle: "Geçmiş",
        exportButton: "Geçmişi Dışa Aktar…",
        exportCaption: "Uzun geçmişi her okuma için bir sütunla CSV olarak kaydeder. Bir saate kadar 5 saniyelik, daha uzun aralıklar 1 dakikalık adımlarla gelir.",
        rangeLabel: "Aralık",
        logFailedTitle: "CSV kaydı durdu",
        exportFailedTitle: "Geçmiş dışa aktarılamadı",
        writeFailedBody: "RyzenStatus “%@” dosyasına yazamadı."
    )

    static let ru = MonitorCSVFeatureStrings(
        section: "Журнал",
        logTitle: "Журнал CSV",
        logButton: "Записывать в CSV…",
        logCaption: "Каждую секунду записывает строку с нагрузкой CPU, температурой, мощностью корпуса, средней частотой и EPP, температурой и мощностью GPU и скоростью каждого вентилятора. Запись прекращается при выходе из RyzenStatus.",
        stop: "Остановить",
        rowsWritten: "Записано строк: %@",
        exportTitle: "История",
        exportButton: "Экспортировать историю…",
        exportCaption: "Сохраняет долгую историю в CSV, по столбцу на показатель. До часа — с шагом 5 секунд, более длинные периоды — с шагом 1 минута.",
        rangeLabel: "Период",
        logFailedTitle: "Запись CSV остановлена",
        exportFailedTitle: "Не удалось экспортировать историю",
        writeFailedBody: "RyzenStatus не удалось записать в «%@»."
    )

    static let es = MonitorCSVFeatureStrings(
        section: "Registro",
        logTitle: "Registro CSV",
        logButton: "Registrar en CSV…",
        logCaption: "Escribe una fila por segundo con la carga de la CPU, la temperatura, la potencia del paquete, el reloj medio y el EPP, la temperatura y la potencia de la GPU y la velocidad de cada ventilador. El registro se detiene al salir de RyzenStatus.",
        stop: "Detener",
        rowsWritten: "Filas escritas: %@",
        exportTitle: "Historial",
        exportButton: "Exportar historial…",
        exportCaption: "Guarda el historial largo en CSV, una columna por lectura. Hasta una hora va en pasos de 5 segundos; los rangos más largos, en pasos de 1 minuto.",
        rangeLabel: "Rango",
        logFailedTitle: "Se detuvo el registro CSV",
        exportFailedTitle: "No se pudo exportar el historial",
        writeFailedBody: "RyzenStatus no pudo escribir en «%@»."
    )

    static let de = MonitorCSVFeatureStrings(
        section: "Protokoll",
        logTitle: "CSV-Protokoll",
        logButton: "In CSV protokollieren …",
        logCaption: "Schreibt jede Sekunde eine Zeile mit CPU-Last, Temperatur, Package-Leistung, mittlerem Takt und EPP, GPU-Temperatur und -Leistung sowie der Drehzahl jedes Lüfters. Das Protokoll endet, wenn RyzenStatus beendet wird.",
        stop: "Stoppen",
        rowsWritten: "Geschriebene Zeilen: %@",
        exportTitle: "Verlauf",
        exportButton: "Verlauf exportieren …",
        exportCaption: "Sichert den Langzeitverlauf als CSV, eine Spalte pro Messwert. Bis zu einer Stunde in 5-Sekunden-Schritten, längere Zeiträume in 1-Minuten-Schritten.",
        rangeLabel: "Zeitraum",
        logFailedTitle: "CSV-Protokoll gestoppt",
        exportFailedTitle: "Verlauf konnte nicht exportiert werden",
        writeFailedBody: "RyzenStatus konnte nicht in „%@“ schreiben."
    )

    static let fr = MonitorCSVFeatureStrings(
        section: "Journal",
        logTitle: "Journal CSV",
        logButton: "Journaliser en CSV…",
        logCaption: "Écrit une ligne par seconde avec la charge du CPU, sa température, la puissance du boîtier, la fréquence moyenne et l’EPP, la température et la puissance du GPU, et la vitesse de chaque ventilateur. Le journal s’arrête quand RyzenStatus quitte.",
        stop: "Arrêter",
        rowsWritten: "Lignes écrites : %@",
        exportTitle: "Historique",
        exportButton: "Exporter l’historique…",
        exportCaption: "Enregistre l’historique long en CSV, une colonne par mesure. Jusqu’à une heure par pas de 5 secondes, les plages plus longues par pas de 1 minute.",
        rangeLabel: "Plage",
        logFailedTitle: "Journal CSV arrêté",
        exportFailedTitle: "Échec de l’export de l’historique",
        writeFailedBody: "RyzenStatus n’a pas pu écrire dans « %@ »."
    )

    static let it = MonitorCSVFeatureStrings(
        section: "Registro",
        logTitle: "Registro CSV",
        logButton: "Registra in CSV…",
        logCaption: "Scrive una riga al secondo con carico della CPU, temperatura, potenza del package, clock medio ed EPP, temperatura e potenza della GPU e velocità di ogni ventola. La registrazione si ferma quando RyzenStatus viene chiuso.",
        stop: "Interrompi",
        rowsWritten: "Righe scritte: %@",
        exportTitle: "Cronologia",
        exportButton: "Esporta cronologia…",
        exportCaption: "Salva la cronologia lunga in CSV, una colonna per lettura. Fino a un'ora a passi di 5 secondi, gli intervalli più lunghi a passi di 1 minuto.",
        rangeLabel: "Intervallo",
        logFailedTitle: "Registrazione CSV interrotta",
        exportFailedTitle: "Esportazione della cronologia non riuscita",
        writeFailedBody: "RyzenStatus non è riuscito a scrivere in “%@”."
    )

    static let ja = MonitorCSVFeatureStrings(
        section: "記録",
        logTitle: "CSVログ",
        logButton: "CSVに記録…",
        logCaption: "CPU使用率、温度、パッケージ電力、平均クロック、EPP、GPUの温度と電力、各ファンの回転数を1秒ごとに1行ずつ書き込みます。RyzenStatusを終了すると記録も止まります。",
        stop: "停止",
        rowsWritten: "書き込んだ行数: %@",
        exportTitle: "履歴",
        exportButton: "履歴を書き出す…",
        exportCaption: "長期履歴を、読み取り値ごとに1列のCSVとして保存します。1時間までは5秒刻み、それより長い範囲は1分刻みです。",
        rangeLabel: "範囲",
        logFailedTitle: "CSVの記録を停止しました",
        exportFailedTitle: "履歴を書き出せませんでした",
        writeFailedBody: "RyzenStatusは“%@”に書き込めませんでした。"
    )

    static let ko = MonitorCSVFeatureStrings(
        section: "기록",
        logTitle: "CSV 기록",
        logButton: "CSV로 기록…",
        logCaption: "CPU 사용률, 온도, 패키지 전력, 평균 클럭과 EPP, GPU 온도와 전력, 각 팬 속도를 1초마다 한 행씩 기록합니다. RyzenStatus를 종료하면 기록도 멈춥니다.",
        stop: "중지",
        rowsWritten: "기록된 행: %@",
        exportTitle: "기록 내역",
        exportButton: "기록 내역 내보내기…",
        exportCaption: "장기 기록 내역을 측정값마다 한 열씩 CSV로 저장합니다. 1시간까지는 5초 간격, 더 긴 범위는 1분 간격입니다.",
        rangeLabel: "범위",
        logFailedTitle: "CSV 기록이 중지됨",
        exportFailedTitle: "기록 내역을 내보내지 못함",
        writeFailedBody: "RyzenStatus가 “%@”에 쓸 수 없습니다."
    )

    static let zhHans = MonitorCSVFeatureStrings(
        section: "记录",
        logTitle: "CSV 日志",
        logButton: "记录到 CSV…",
        logCaption: "每秒写入一行，包含 CPU 负载、温度、封装功耗、平均频率和 EPP，GPU 温度和功耗，以及每个风扇的转速。退出 RyzenStatus 时停止记录。",
        stop: "停止",
        rowsWritten: "已写入行数：%@",
        exportTitle: "历史记录",
        exportButton: "导出历史记录…",
        exportCaption: "将长期历史记录存为 CSV，每项读数一列。一小时以内按 5 秒一步，更长的范围按 1 分钟一步。",
        rangeLabel: "范围",
        logFailedTitle: "CSV 记录已停止",
        exportFailedTitle: "无法导出历史记录",
        writeFailedBody: "RyzenStatus 无法写入“%@”。"
    )

    static let zhTW = MonitorCSVFeatureStrings(
        section: "記錄",
        logTitle: "CSV 記錄檔",
        logButton: "記錄到 CSV…",
        logCaption: "每秒寫入一列，包含 CPU 負載、溫度、封裝功耗、平均時脈和 EPP，GPU 溫度和功耗，以及每個風扇的轉速。結束 RyzenStatus 時停止記錄。",
        stop: "停止",
        rowsWritten: "已寫入列數：%@",
        exportTitle: "歷史記錄",
        exportButton: "輸出歷史記錄…",
        exportCaption: "將長期歷史記錄存成 CSV，每項讀數一欄。一小時以內每 5 秒一筆，更長的範圍每 1 分鐘一筆。",
        rangeLabel: "範圍",
        logFailedTitle: "CSV 記錄已停止",
        exportFailedTitle: "無法輸出歷史記錄",
        writeFailedBody: "RyzenStatus 無法寫入「%@」。"
    )

    static let zhHK = MonitorCSVFeatureStrings(
        section: "記錄",
        logTitle: "CSV 記錄檔",
        logButton: "記錄到 CSV…",
        logCaption: "每秒寫入一行，包含 CPU 負載、溫度、封裝功耗、平均時脈和 EPP，GPU 溫度和功耗，以及每把風扇的轉速。結束 RyzenStatus 時停止記錄。",
        stop: "停止",
        rowsWritten: "已寫入行數：%@",
        exportTitle: "歷史記錄",
        exportButton: "匯出歷史記錄…",
        exportCaption: "將長期歷史記錄儲存為 CSV，每項讀數一欄。一小時以內每 5 秒一筆，更長的範圍每 1 分鐘一筆。",
        rangeLabel: "範圍",
        logFailedTitle: "CSV 記錄已停止",
        exportFailedTitle: "無法匯出歷史記錄",
        writeFailedBody: "RyzenStatus 無法寫入「%@」。"
    )

    static let sk = MonitorCSVFeatureStrings(
        section: "Záznam",
        logTitle: "Záznam CSV",
        logButton: "Zaznamenávať do CSV…",
        logCaption: "Každú sekundu zapíše riadok so záťažou CPU, teplotou, príkonom puzdra, priemerným taktom a EPP, teplotou a príkonom GPU a otáčkami každého ventilátora. Záznam sa zastaví pri ukončení RyzenStatus.",
        stop: "Zastaviť",
        rowsWritten: "Zapísané riadky: %@",
        exportTitle: "História",
        exportButton: "Exportovať históriu…",
        exportCaption: "Uloží dlhú históriu ako CSV, jeden stĺpec na meranie. Do jednej hodiny po 5 sekundách, dlhšie rozsahy po 1 minúte.",
        rangeLabel: "Rozsah",
        logFailedTitle: "Záznam CSV sa zastavil",
        exportFailedTitle: "Históriu sa nepodarilo exportovať",
        writeFailedBody: "RyzenStatus nemohol zapisovať do „%@“."
    )

    static let uk = MonitorCSVFeatureStrings(
        section: "Журнал",
        logTitle: "Журнал CSV",
        logButton: "Записувати в CSV…",
        logCaption: "Щосекунди записує рядок із навантаженням CPU, температурою, потужністю корпусу, середньою частотою та EPP, температурою й потужністю GPU і швидкістю кожного вентилятора. Запис зупиняється, коли RyzenStatus завершує роботу.",
        stop: "Зупинити",
        rowsWritten: "Записано рядків: %@",
        exportTitle: "Історія",
        exportButton: "Експортувати історію…",
        exportCaption: "Зберігає довгу історію в CSV, по стовпцю на показник. До години — з кроком 5 секунд, довші періоди — з кроком 1 хвилина.",
        rangeLabel: "Період",
        logFailedTitle: "Запис CSV зупинено",
        exportFailedTitle: "Не вдалося експортувати історію",
        writeFailedBody: "RyzenStatus не вдалося записати в «%@»."
    )
}
