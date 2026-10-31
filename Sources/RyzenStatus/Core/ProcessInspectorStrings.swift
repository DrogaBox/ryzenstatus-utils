// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Strings for the process inspector window. Card titles keep their capitals
/// where the language has them.
struct ProcessInspectorStrings {
    /// The process name as `%@`, its PID as `%d`.
    let windowTitleFormat: String
    /// The PID as `%d`.
    let pidFormat: String
    let leakTitle: String
    let leakDetail: String
    let cpuLoad: String
    let residentMemory: String
    let networkIO: String
    let networkIdle: String
    let executablePath: String
    let pathUnavailable: String
    let copied: String
    let copyPath: String
    let revealInFinder: String
    let processRole: String
    let done: String
    let terminate: String
    /// The process name as `%@`.
    let forceQuitTitleFormat: String
    /// The PID as `%d`.
    let forceQuitMessageFormat: String
    let cancel: String
    let forceQuit: String
    let terminateFailed: String
    let categorySystem: String
    let categoryApp: String
    let categoryHelper: String
    let categoryBackground: String
    let categoryDeveloper: String
    let categorySecurity: String
    /// What a process of each kind does, shown under the role heading.
    let roleSystem: String
    let roleApp: String
    let roleBackground: String

    func categoryName(_ category: ProcessCategory) -> String {
        switch category {
        case .system: return categorySystem
        case .app: return categoryApp
        case .helper: return categoryHelper
        case .background: return categoryBackground
        case .developer: return categoryDeveloper
        case .security: return categorySecurity
        }
    }

    func role(_ category: ProcessCategory) -> String {
        switch category {
        case .system: return roleSystem
        case .app: return roleApp
        case .helper, .background, .developer, .security: return roleBackground
        }
    }
}

extension FeatureStrings {
    static func processInspector(_ language: AppLanguage) -> ProcessInspectorStrings {
        switch language {
        case .enUS: return ProcessInspectorStrings(
            windowTitleFormat: "Process Inspector — %@ (%d)", pidFormat: "PID: %d",
            leakTitle: "Continuous Memory Growth Detected",
            leakDetail: "This process is showing sustained memory leaks over 20+ minutes.",
            cpuLoad: "CPU LOAD", residentMemory: "RESIDENT RAM (RSS)", networkIO: "NETWORK I/O",
            networkIdle: "0 B/s (Inactive)", executablePath: "EXECUTABLE PATH", pathUnavailable: "Path unavailable",
            copied: "Copied", copyPath: "Copy Path", revealInFinder: "Reveal in Finder",
            processRole: "PROCESS ROLE & DESCRIPTION", done: "Done", terminate: "Terminate Process",
            forceQuitTitleFormat: "Force Quit %@?",
            forceQuitMessageFormat: "Are you sure you want to send SIGKILL to PID %d? Any unsaved data will be lost.",
            cancel: "Cancel", forceQuit: "Force Quit", terminateFailed: "The process could not be stopped.",
            categorySystem: "System", categoryApp: "App", categoryHelper: "Helper",
            categoryBackground: "Background", categoryDeveloper: "Developer", categorySecurity: "Security",
            roleSystem: "Part of macOS itself.", roleApp: "Application process running on macOS.",
            roleBackground: "Background service or helper process.")
        case .ptBR: return ProcessInspectorStrings(
            windowTitleFormat: "Inspetor de processos — %@ (%d)", pidFormat: "PID: %d",
            leakTitle: "Crescimento contínuo de memória detectado",
            leakDetail: "Este processo mostra vazamentos de memória contínuos há mais de 20 minutos.",
            cpuLoad: "CARGA DA CPU", residentMemory: "RAM RESIDENTE (RSS)", networkIO: "E/S DE REDE",
            networkIdle: "0 B/s (inativo)", executablePath: "CAMINHO DO EXECUTÁVEL", pathUnavailable: "Caminho indisponível",
            copied: "Copiado", copyPath: "Copiar caminho", revealInFinder: "Mostrar no Finder",
            processRole: "FUNÇÃO E DESCRIÇÃO DO PROCESSO", done: "OK", terminate: "Encerrar processo",
            forceQuitTitleFormat: "Forçar encerramento de %@?",
            forceQuitMessageFormat: "Tem certeza de que deseja enviar SIGKILL ao PID %d? Os dados não salvos serão perdidos.",
            cancel: "Cancelar", forceQuit: "Forçar encerramento", terminateFailed: "Não foi possível encerrar o processo.",
            categorySystem: "Sistema", categoryApp: "App", categoryHelper: "Auxiliar",
            categoryBackground: "Segundo plano", categoryDeveloper: "Desenvolvedor", categorySecurity: "Segurança",
            roleSystem: "Faz parte do próprio macOS.", roleApp: "Processo de aplicativo em execução no macOS.",
            roleBackground: "Serviço em segundo plano ou processo auxiliar.")
        case .tr: return ProcessInspectorStrings(
            windowTitleFormat: "Süreç Denetçisi — %@ (%d)", pidFormat: "PID: %d",
            leakTitle: "Sürekli bellek artışı algılandı",
            leakDetail: "Bu süreç 20 dakikadan uzun süredir kesintisiz bellek sızıntısı gösteriyor.",
            cpuLoad: "CPU YÜKÜ", residentMemory: "YERLEŞİK RAM (RSS)", networkIO: "AĞ G/Ç",
            networkIdle: "0 B/sn (etkin değil)", executablePath: "YÜRÜTÜLEBİLİR DOSYA YOLU", pathUnavailable: "Yol kullanılamıyor",
            copied: "Kopyalandı", copyPath: "Yolu kopyala", revealInFinder: "Finder’da göster",
            processRole: "SÜRECİN ROLÜ VE AÇIKLAMASI", done: "Bitti", terminate: "Süreci sonlandır",
            forceQuitTitleFormat: "%@ zorla kapatılsın mı?",
            forceQuitMessageFormat: "PID %d sürecine SIGKILL göndermek istediğinizden emin misiniz? Kaydedilmemiş veriler kaybolur.",
            cancel: "Vazgeç", forceQuit: "Zorla kapat", terminateFailed: "Süreç durdurulamadı.",
            categorySystem: "Sistem", categoryApp: "Uygulama", categoryHelper: "Yardımcı",
            categoryBackground: "Arka plan", categoryDeveloper: "Geliştirici", categorySecurity: "Güvenlik",
            roleSystem: "macOS’in bir parçası.", roleApp: "macOS’te çalışan bir uygulama süreci.",
            roleBackground: "Arka plan hizmeti veya yardımcı süreç.")
        case .ru: return ProcessInspectorStrings(
            windowTitleFormat: "Инспектор процессов — %@ (%d)", pidFormat: "PID: %d",
            leakTitle: "Обнаружен непрерывный рост памяти",
            leakDetail: "Этот процесс показывает устойчивые утечки памяти более 20 минут.",
            cpuLoad: "ЗАГРУЗКА ЦП", residentMemory: "РЕЗИДЕНТНАЯ ПАМЯТЬ (RSS)", networkIO: "СЕТЕВОЙ ВВОД-ВЫВОД",
            networkIdle: "0 Б/с (неактивен)", executablePath: "ПУТЬ К ИСПОЛНЯЕМОМУ ФАЙЛУ", pathUnavailable: "Путь недоступен",
            copied: "Скопировано", copyPath: "Скопировать путь", revealInFinder: "Показать в Finder",
            processRole: "РОЛЬ И ОПИСАНИЕ ПРОЦЕССА", done: "Готово", terminate: "Завершить процесс",
            forceQuitTitleFormat: "Завершить %@ принудительно?",
            forceQuitMessageFormat: "Отправить SIGKILL процессу с PID %d? Несохраненные данные будут потеряны.",
            cancel: "Отменить", forceQuit: "Завершить принудительно", terminateFailed: "Не удалось остановить процесс.",
            categorySystem: "Система", categoryApp: "Приложение", categoryHelper: "Помощник",
            categoryBackground: "Фоновый", categoryDeveloper: "Разработка", categorySecurity: "Безопасность",
            roleSystem: "Часть самой macOS.", roleApp: "Процесс приложения, работающего в macOS.",
            roleBackground: "Фоновая служба или вспомогательный процесс.")
        case .es: return ProcessInspectorStrings(
            windowTitleFormat: "Inspector de procesos — %@ (%d)", pidFormat: "PID: %d",
            leakTitle: "Crecimiento continuo de memoria detectado",
            leakDetail: "Este proceso muestra fugas de memoria sostenidas durante más de 20 minutos.",
            cpuLoad: "CARGA DE CPU", residentMemory: "RAM RESIDENTE (RSS)", networkIO: "E/S DE RED",
            networkIdle: "0 B/s (inactivo)", executablePath: "RUTA DEL EJECUTABLE", pathUnavailable: "Ruta no disponible",
            copied: "Copiado", copyPath: "Copiar ruta", revealInFinder: "Mostrar en Finder",
            processRole: "FUNCIÓN Y DESCRIPCIÓN DEL PROCESO", done: "Listo", terminate: "Terminar proceso",
            forceQuitTitleFormat: "¿Forzar la salida de %@?",
            forceQuitMessageFormat: "¿Seguro que quieres enviar SIGKILL al PID %d? Se perderán los datos sin guardar.",
            cancel: "Cancelar", forceQuit: "Forzar salida", terminateFailed: "No se pudo detener el proceso.",
            categorySystem: "Sistema", categoryApp: "App", categoryHelper: "Auxiliar",
            categoryBackground: "Segundo plano", categoryDeveloper: "Desarrollo", categorySecurity: "Seguridad",
            roleSystem: "Forma parte del propio macOS.", roleApp: "Proceso de una aplicación que se ejecuta en macOS.",
            roleBackground: "Servicio en segundo plano o proceso auxiliar.")
        case .de: return ProcessInspectorStrings(
            windowTitleFormat: "Prozessinspektor — %@ (%d)", pidFormat: "PID: %d",
            leakTitle: "Stetiges Speicherwachstum erkannt",
            leakDetail: "Dieser Prozess zeigt seit über 20 Minuten anhaltende Speicherlecks.",
            cpuLoad: "CPU-LAST", residentMemory: "BELEGTER RAM (RSS)", networkIO: "NETZWERK-E/A",
            networkIdle: "0 B/s (inaktiv)", executablePath: "PFAD DER AUSFÜHRBAREN DATEI", pathUnavailable: "Pfad nicht verfügbar",
            copied: "Kopiert", copyPath: "Pfad kopieren", revealInFinder: "Im Finder zeigen",
            processRole: "ROLLE UND BESCHREIBUNG DES PROZESSES", done: "Fertig", terminate: "Prozess beenden",
            forceQuitTitleFormat: "%@ sofort beenden?",
            forceQuitMessageFormat: "Möchtest du wirklich SIGKILL an PID %d senden? Nicht gesicherte Daten gehen verloren.",
            cancel: "Abbrechen", forceQuit: "Sofort beenden", terminateFailed: "Der Prozess konnte nicht gestoppt werden.",
            categorySystem: "System", categoryApp: "App", categoryHelper: "Hilfsprozess",
            categoryBackground: "Hintergrund", categoryDeveloper: "Entwickler", categorySecurity: "Sicherheit",
            roleSystem: "Teil von macOS selbst.", roleApp: "App-Prozess, der unter macOS läuft.",
            roleBackground: "Hintergrunddienst oder Hilfsprozess.")
        case .fr: return ProcessInspectorStrings(
            windowTitleFormat: "Inspecteur de processus — %@ (%d)", pidFormat: "PID : %d",
            leakTitle: "Croissance continue de la mémoire détectée",
            leakDetail: "Ce processus présente des fuites de mémoire persistantes depuis plus de 20 minutes.",
            cpuLoad: "CHARGE CPU", residentMemory: "RAM RÉSIDENTE (RSS)", networkIO: "E/S RÉSEAU",
            networkIdle: "0 o/s (inactif)", executablePath: "CHEMIN DE L’EXÉCUTABLE", pathUnavailable: "Chemin indisponible",
            copied: "Copié", copyPath: "Copier le chemin", revealInFinder: "Afficher dans le Finder",
            processRole: "RÔLE ET DESCRIPTION DU PROCESSUS", done: "OK", terminate: "Terminer le processus",
            forceQuitTitleFormat: "Forcer %@ à quitter ?",
            forceQuitMessageFormat: "Voulez-vous vraiment envoyer SIGKILL au PID %d ? Les données non enregistrées seront perdues.",
            cancel: "Annuler", forceQuit: "Forcer à quitter", terminateFailed: "Impossible d’arrêter le processus.",
            categorySystem: "Système", categoryApp: "App", categoryHelper: "Assistant",
            categoryBackground: "Arrière-plan", categoryDeveloper: "Développeur", categorySecurity: "Sécurité",
            roleSystem: "Fait partie de macOS.", roleApp: "Processus d’une application exécutée sur macOS.",
            roleBackground: "Service d’arrière-plan ou processus assistant.")
        case .it: return ProcessInspectorStrings(
            windowTitleFormat: "Ispettore processi — %@ (%d)", pidFormat: "PID: %d",
            leakTitle: "Rilevata crescita continua della memoria",
            leakDetail: "Questo processo mostra perdite di memoria costanti da oltre 20 minuti.",
            cpuLoad: "CARICO CPU", residentMemory: "RAM RESIDENTE (RSS)", networkIO: "I/O DI RETE",
            networkIdle: "0 B/s (inattivo)", executablePath: "PERCORSO DELL’ESEGUIBILE", pathUnavailable: "Percorso non disponibile",
            copied: "Copiato", copyPath: "Copia percorso", revealInFinder: "Mostra nel Finder",
            processRole: "RUOLO E DESCRIZIONE DEL PROCESSO", done: "Fine", terminate: "Termina processo",
            forceQuitTitleFormat: "Uscire forzatamente da %@?",
            forceQuitMessageFormat: "Vuoi davvero inviare SIGKILL al PID %d? I dati non salvati andranno persi.",
            cancel: "Annulla", forceQuit: "Uscita forzata", terminateFailed: "Impossibile arrestare il processo.",
            categorySystem: "Sistema", categoryApp: "App", categoryHelper: "Supporto",
            categoryBackground: "In background", categoryDeveloper: "Sviluppo", categorySecurity: "Sicurezza",
            roleSystem: "Fa parte di macOS stesso.", roleApp: "Processo di un’app in esecuzione su macOS.",
            roleBackground: "Servizio in background o processo di supporto.")
        case .ja: return ProcessInspectorStrings(
            windowTitleFormat: "プロセスインスペクタ — %@ (%d)", pidFormat: "PID: %d",
            leakTitle: "メモリの継続的な増加を検出",
            leakDetail: "このプロセスは20分以上にわたってメモリリークが続いています。",
            cpuLoad: "CPU負荷", residentMemory: "常駐メモリ（RSS）", networkIO: "ネットワークI/O",
            networkIdle: "0 B/s（非アクティブ）", executablePath: "実行ファイルのパス", pathUnavailable: "パスを取得できません",
            copied: "コピーしました", copyPath: "パスをコピー", revealInFinder: "Finderに表示",
            processRole: "プロセスの役割と説明", done: "完了", terminate: "プロセスを終了",
            forceQuitTitleFormat: "%@を強制終了しますか？",
            forceQuitMessageFormat: "PID %dにSIGKILLを送信してもよろしいですか？保存されていないデータは失われます。",
            cancel: "キャンセル", forceQuit: "強制終了", terminateFailed: "プロセスを停止できませんでした。",
            categorySystem: "システム", categoryApp: "アプリ", categoryHelper: "ヘルパー",
            categoryBackground: "バックグラウンド", categoryDeveloper: "開発", categorySecurity: "セキュリティ",
            roleSystem: "macOS自体の一部です。", roleApp: "macOSで実行中のアプリのプロセスです。",
            roleBackground: "バックグラウンドサービスまたはヘルパープロセスです。")
        case .ko: return ProcessInspectorStrings(
            windowTitleFormat: "프로세스 인스펙터 — %@ (%d)", pidFormat: "PID: %d",
            leakTitle: "지속적인 메모리 증가 감지됨",
            leakDetail: "이 프로세스는 20분 이상 메모리 누수가 계속되고 있습니다.",
            cpuLoad: "CPU 부하", residentMemory: "상주 메모리(RSS)", networkIO: "네트워크 I/O",
            networkIdle: "0 B/s(비활성)", executablePath: "실행 파일 경로", pathUnavailable: "경로를 사용할 수 없음",
            copied: "복사됨", copyPath: "경로 복사", revealInFinder: "Finder에서 보기",
            processRole: "프로세스 역할 및 설명", done: "완료", terminate: "프로세스 종료",
            forceQuitTitleFormat: "%@을(를) 강제 종료하시겠습니까?",
            forceQuitMessageFormat: "PID %d에 SIGKILL을 보내시겠습니까? 저장하지 않은 데이터는 손실됩니다.",
            cancel: "취소", forceQuit: "강제 종료", terminateFailed: "프로세스를 중지할 수 없습니다.",
            categorySystem: "시스템", categoryApp: "앱", categoryHelper: "도우미",
            categoryBackground: "백그라운드", categoryDeveloper: "개발자", categorySecurity: "보안",
            roleSystem: "macOS 자체의 일부입니다.", roleApp: "macOS에서 실행 중인 앱 프로세스입니다.",
            roleBackground: "백그라운드 서비스 또는 도우미 프로세스입니다.")
        case .zhHans: return ProcessInspectorStrings(
            windowTitleFormat: "进程检查器 — %@ (%d)", pidFormat: "PID：%d",
            leakTitle: "检测到内存持续增长",
            leakDetail: "此进程已持续泄漏内存超过 20 分钟。",
            cpuLoad: "CPU 负载", residentMemory: "常驻内存（RSS）", networkIO: "网络 I/O",
            networkIdle: "0 B/s（无活动）", executablePath: "可执行文件路径", pathUnavailable: "路径不可用",
            copied: "已拷贝", copyPath: "拷贝路径", revealInFinder: "在访达中显示",
            processRole: "进程角色与说明", done: "完成", terminate: "终止进程",
            forceQuitTitleFormat: "要强制退出“%@”吗？",
            forceQuitMessageFormat: "确定要向 PID %d 发送 SIGKILL 吗？未存储的数据将会丢失。",
            cancel: "取消", forceQuit: "强制退出", terminateFailed: "无法停止该进程。",
            categorySystem: "系统", categoryApp: "应用", categoryHelper: "辅助",
            categoryBackground: "后台", categoryDeveloper: "开发", categorySecurity: "安全",
            roleSystem: "macOS 自身的一部分。", roleApp: "在 macOS 上运行的应用进程。",
            roleBackground: "后台服务或辅助进程。")
        case .zhTW: return ProcessInspectorStrings(
            windowTitleFormat: "程序檢閱器 — %@ (%d)", pidFormat: "PID：%d",
            leakTitle: "偵測到記憶體持續增加",
            leakDetail: "此程序已持續記憶體洩漏超過 20 分鐘。",
            cpuLoad: "CPU 負載", residentMemory: "常駐記憶體（RSS）", networkIO: "網路 I/O",
            networkIdle: "0 B/s（閒置）", executablePath: "執行檔路徑", pathUnavailable: "無法取得路徑",
            copied: "已拷貝", copyPath: "拷貝路徑", revealInFinder: "在 Finder 中顯示",
            processRole: "程序角色與說明", done: "完成", terminate: "終止程序",
            forceQuitTitleFormat: "要強制結束「%@」嗎？",
            forceQuitMessageFormat: "確定要傳送 SIGKILL 給 PID %d 嗎？未儲存的資料將會遺失。",
            cancel: "取消", forceQuit: "強制結束", terminateFailed: "無法停止此程序。",
            categorySystem: "系統", categoryApp: "App", categoryHelper: "輔助",
            categoryBackground: "背景", categoryDeveloper: "開發", categorySecurity: "安全性",
            roleSystem: "macOS 本身的一部分。", roleApp: "在 macOS 上執行的 App 程序。",
            roleBackground: "背景服務或輔助程序。")
        case .zhHK: return ProcessInspectorStrings(
            windowTitleFormat: "程序檢查器 — %@ (%d)", pidFormat: "PID：%d",
            leakTitle: "偵測到記憶體持續增加",
            leakDetail: "此程序已持續記憶體洩漏超過 20 分鐘。",
            cpuLoad: "CPU 負載", residentMemory: "常駐記憶體（RSS）", networkIO: "網絡 I/O",
            networkIdle: "0 B/s（閒置）", executablePath: "執行檔路徑", pathUnavailable: "無法取得路徑",
            copied: "已拷貝", copyPath: "拷貝路徑", revealInFinder: "在 Finder 中顯示",
            processRole: "程序角色與說明", done: "完成", terminate: "終止程序",
            forceQuitTitleFormat: "要強制結束「%@」嗎？",
            forceQuitMessageFormat: "確定要傳送 SIGKILL 至 PID %d 嗎？未儲存的資料將會遺失。",
            cancel: "取消", forceQuit: "強制結束", terminateFailed: "無法停止此程序。",
            categorySystem: "系統", categoryApp: "App", categoryHelper: "輔助",
            categoryBackground: "背景", categoryDeveloper: "開發", categorySecurity: "安全性",
            roleSystem: "macOS 本身的一部分。", roleApp: "在 macOS 上執行的 App 程序。",
            roleBackground: "背景服務或輔助程序。")
        case .sk: return ProcessInspectorStrings(
            windowTitleFormat: "Inšpektor procesov — %@ (%d)", pidFormat: "PID: %d",
            leakTitle: "Zistený nepretržitý rast pamäte",
            leakDetail: "Tento proces vykazuje trvalé úniky pamäte dlhšie ako 20 minút.",
            cpuLoad: "ZÁŤAŽ CPU", residentMemory: "REZIDENTNÁ RAM (RSS)", networkIO: "SIEŤOVÉ V/V",
            networkIdle: "0 B/s (nečinné)", executablePath: "CESTA K SPUSTITEĽNÉMU SÚBORU", pathUnavailable: "Cesta nie je k dispozícii",
            copied: "Skopírované", copyPath: "Kopírovať cestu", revealInFinder: "Zobraziť vo Finderi",
            processRole: "ÚLOHA A POPIS PROCESU", done: "Hotovo", terminate: "Ukončiť proces",
            forceQuitTitleFormat: "Vynútiť ukončenie %@?",
            forceQuitMessageFormat: "Naozaj chcete poslať SIGKILL procesu s PID %d? Neuložené údaje sa stratia.",
            cancel: "Zrušiť", forceQuit: "Vynútiť ukončenie", terminateFailed: "Proces sa nepodarilo zastaviť.",
            categorySystem: "Systém", categoryApp: "Aplikácia", categoryHelper: "Pomocník",
            categoryBackground: "Na pozadí", categoryDeveloper: "Vývojár", categorySecurity: "Zabezpečenie",
            roleSystem: "Súčasť samotného macOS.", roleApp: "Proces aplikácie spustenej v macOS.",
            roleBackground: "Služba na pozadí alebo pomocný proces.")
        case .uk: return ProcessInspectorStrings(
            windowTitleFormat: "Інспектор процесів — %@ (%d)", pidFormat: "PID: %d",
            leakTitle: "Виявлено постійне зростання пам’яті",
            leakDetail: "Цей процес демонструє стійкі витоки пам’яті понад 20 хвилин.",
            cpuLoad: "НАВАНТАЖЕННЯ ЦП", residentMemory: "РЕЗИДЕНТНА ПАМ’ЯТЬ (RSS)", networkIO: "МЕРЕЖЕВЕ ВВЕДЕННЯ-ВИВЕДЕННЯ",
            networkIdle: "0 Б/с (неактивний)", executablePath: "ШЛЯХ ДО ВИКОНУВАНОГО ФАЙЛУ", pathUnavailable: "Шлях недоступний",
            copied: "Скопійовано", copyPath: "Скопіювати шлях", revealInFinder: "Показати у Finder",
            processRole: "РОЛЬ І ОПИС ПРОЦЕСУ", done: "Готово", terminate: "Завершити процес",
            forceQuitTitleFormat: "Примусово завершити %@?",
            forceQuitMessageFormat: "Надіслати SIGKILL процесу з PID %d? Незбережені дані буде втрачено.",
            cancel: "Скасувати", forceQuit: "Примусово завершити", terminateFailed: "Не вдалося зупинити процес.",
            categorySystem: "Система", categoryApp: "Програма", categoryHelper: "Помічник",
            categoryBackground: "Фоновий", categoryDeveloper: "Розробка", categorySecurity: "Безпека",
            roleSystem: "Частина самої macOS.", roleApp: "Процес програми, що працює в macOS.",
            roleBackground: "Фонова служба або допоміжний процес.")
        }
    }
}
