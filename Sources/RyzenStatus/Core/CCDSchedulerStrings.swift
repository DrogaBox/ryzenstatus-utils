// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Settings › AMD Ryzen Power › CCD scheduler (AMDCCDScheduler.kext).
struct CCDSchedulerStrings {
    let header: String
    let footer: String
    let statusActive: String
    let statusOff: String
    /// mode 2: the 0.1.0 behaviour, kept for comparisons
    let statusLegacy: String
    let statusNotRun: String
    let statusSymbolMissing: String
    let statusLayoutMismatch: String
    let statusRouteFailed: String
    let statusSingleL3: String
    let statusUnknown: String
    let toggle: String
    let toggleNote: String
    let statNew: String
    let statKept: String
    let statSame: String
    let statFirst: String
    /// home CCD had no free physical core (kext 0.2.1 and later)
    let statFull: String
    /// %d = number of CCDs (L3 caches)
    let ccdCount: String
    /// %d = number of CCDs
    let notLoadedHint: String
    let adminPrompt: String
    let toggleFailed: String
    let logTitle: String
}

extension L10n {
    var ccdScheduler: CCDSchedulerStrings {
        CCDSchedulerStrings.current(language)
    }
}

extension CCDSchedulerStrings {
    static func current(_ language: AppLanguage) -> CCDSchedulerStrings {
        switch language {
        case .enUS: return .enUS
        case .es: return .es
        case .ptBR: return .ptBR
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ru: return .ru
        case .tr: return .tr
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .sk: return .sk
        case .uk: return .uk
        }
    }

    static let enUS = CCDSchedulerStrings(
        header: "CCD scheduler",
        footer: "Keeps the threads of each app on one CCD while that CCD has a free core, so they share its L3 cache instead of crossing the Infinity Fabric. Threads that pass data to each other gain: a Node worker pool ran about 12% faster on a 5900XT. Work that fills every core still spreads over both CCDs, at the same speed. Needs AMDCCDScheduler.kext.",
        statusActive: "Active",
        statusOff: "Switched off",
        statusLegacy: "Comparison mode (0.1.0: new threads only)",
        statusNotRun: "Loaded, waiting for Lilu",
        statusSymbolMissing: "Not installed: kernel symbols missing",
        statusLayoutMismatch: "Not installed: this macOS kernel is not supported yet",
        statusRouteFailed: "Not installed: Lilu could not hook the scheduler",
        statusSingleL3: "Not needed: this CPU has a single L3 cache",
        statusUnknown: "Unknown state",
        toggle: "Keep each app's threads on one CCD",
        toggleNote: "Until restart. Add ccdmode=0 to boot-args to start with it off.",
        statNew: "Placements checked",
        statKept: "Moved to their app's CCD",
        statSame: "Already on their app's CCD",
        statFirst: "Apps given a CCD",
        statFull: "Left to macOS: CCD busy",
        ccdCount: "%d CCDs, one L3 cache each",
        notLoadedHint: "This CPU has %d CCDs. AMDCCDScheduler.kext keeps each app's threads on one of them; add it to OpenCore after Lilu.",
        adminPrompt: "RyzenStatus needs your password to change the CCD scheduler.",
        toggleFailed: "The mode was not changed.",
        logTitle: "Kext log"
    )

    static let es = CCDSchedulerStrings(
        header: "Planificador de CCD",
        footer: "Mantiene los hilos de cada app en un mismo CCD mientras ese CCD tenga un núcleo libre, para que compartan su caché L3 en vez de cruzar el Infinity Fabric. Ganan los hilos que se pasan datos entre sí: un grupo de workers de Node anduvo cerca de 12 % más rápido en un 5900XT. El trabajo que llena todos los núcleos se sigue repartiendo entre los dos CCD, a la misma velocidad. Necesita AMDCCDScheduler.kext.",
        statusActive: "Activo",
        statusOff: "Apagado",
        statusLegacy: "Modo de comparación (0.1.0: solo hilos nuevos)",
        statusNotRun: "Cargado, esperando a Lilu",
        statusSymbolMissing: "No instalado: faltan símbolos del kernel",
        statusLayoutMismatch: "No instalado: este kernel de macOS todavía no está soportado",
        statusRouteFailed: "No instalado: Lilu no pudo enganchar el planificador",
        statusSingleL3: "No hace falta: este CPU tiene una sola caché L3",
        statusUnknown: "Estado desconocido",
        toggle: "Mantener los hilos de cada app en un CCD",
        toggleNote: "Hasta reiniciar. Agregá ccdmode=0 a los boot-args para que arranque apagado.",
        statNew: "Ubicaciones revisadas",
        statKept: "Llevados al CCD de su app",
        statSame: "Ya estaban en el CCD de su app",
        statFirst: "Apps con CCD asignado",
        statFull: "Dejados a macOS: CCD ocupado",
        ccdCount: "%d CCD, cada uno con su caché L3",
        notLoadedHint: "Este CPU tiene %d CCD. AMDCCDScheduler.kext mantiene los hilos de cada app en uno de ellos; agregalo en OpenCore después de Lilu.",
        adminPrompt: "RyzenStatus necesita tu contraseña para cambiar el planificador de CCD.",
        toggleFailed: "El modo no se cambió.",
        logTitle: "Registro del kext"
    )

    static let ptBR = CCDSchedulerStrings(
        header: "Agendador de CCD",
        footer: "Mantém as threads de cada app em um mesmo CCD enquanto esse CCD tiver um núcleo livre, para que compartilhem o cache L3 em vez de atravessar o Infinity Fabric. Ganham as threads que trocam dados entre si: um pool de workers do Node ficou cerca de 12% mais rápido em um 5900XT. Trabalho que ocupa todos os núcleos continua dividido entre os dois CCDs, na mesma velocidade. Requer AMDCCDScheduler.kext.",
        statusActive: "Ativo",
        statusOff: "Desligado",
        statusLegacy: "Modo de comparação (0.1.0: só threads novas)",
        statusNotRun: "Carregado, aguardando o Lilu",
        statusSymbolMissing: "Não instalado: faltam símbolos do kernel",
        statusLayoutMismatch: "Não instalado: este kernel do macOS ainda não é suportado",
        statusRouteFailed: "Não instalado: o Lilu não conseguiu interceptar o agendador",
        statusSingleL3: "Desnecessário: esta CPU tem um único cache L3",
        statusUnknown: "Estado desconhecido",
        toggle: "Manter as threads de cada app em um CCD",
        toggleNote: "Até reiniciar. Adicione ccdmode=0 aos boot-args para iniciar desligado.",
        statNew: "Posicionamentos verificados",
        statKept: "Levadas ao CCD do app",
        statSame: "Já estavam no CCD do app",
        statFirst: "Apps com um CCD atribuído",
        statFull: "Deixadas ao macOS: CCD ocupado",
        ccdCount: "%d CCDs, cada um com seu cache L3",
        notLoadedHint: "Esta CPU tem %d CCDs. O AMDCCDScheduler.kext mantém as threads de cada app em um deles; adicione-o no OpenCore depois do Lilu.",
        adminPrompt: "O RyzenStatus precisa da sua senha para alterar o agendador de CCD.",
        toggleFailed: "O modo não foi alterado.",
        logTitle: "Log do kext"
    )

    static let de = CCDSchedulerStrings(
        header: "CCD-Scheduler",
        footer: "Hält die Threads jeder App auf einem CCD, solange dieser einen freien Kern hat, damit sie dessen L3-Cache teilen, statt über die Infinity Fabric zu gehen. Threads, die einander Daten zureichen, profitieren: ein Node-Worker-Pool lief auf einem 5900XT etwa 12 % schneller. Arbeit, die alle Kerne füllt, verteilt sich weiter auf beide CCDs, gleich schnell. Benötigt AMDCCDScheduler.kext.",
        statusActive: "Aktiv",
        statusOff: "Ausgeschaltet",
        statusLegacy: "Vergleichsmodus (0.1.0: nur neue Threads)",
        statusNotRun: "Geladen, wartet auf Lilu",
        statusSymbolMissing: "Nicht installiert: Kernel-Symbole fehlen",
        statusLayoutMismatch: "Nicht installiert: dieser macOS-Kernel wird noch nicht unterstützt",
        statusRouteFailed: "Nicht installiert: Lilu konnte den Scheduler nicht einhaken",
        statusSingleL3: "Nicht nötig: diese CPU hat nur einen L3-Cache",
        statusUnknown: "Unbekannter Zustand",
        toggle: "Threads jeder App auf einem CCD halten",
        toggleNote: "Bis zum Neustart. Mit ccdmode=0 in den Boot-Args startet er ausgeschaltet.",
        statNew: "Geprüfte Platzierungen",
        statKept: "Auf den CCD ihrer App geholt",
        statSame: "Schon auf dem CCD ihrer App",
        statFirst: "Apps mit zugewiesenem CCD",
        statFull: "macOS überlassen: CCD belegt",
        ccdCount: "%d CCDs, je ein L3-Cache",
        notLoadedHint: "Diese CPU hat %d CCDs. AMDCCDScheduler.kext hält die Threads jeder App auf einem davon; in OpenCore nach Lilu hinzufügen.",
        adminPrompt: "RyzenStatus benötigt dein Passwort, um den CCD-Scheduler zu ändern.",
        toggleFailed: "Der Modus wurde nicht geändert.",
        logTitle: "Kext-Protokoll"
    )

    static let fr = CCDSchedulerStrings(
        header: "Planificateur de CCD",
        footer: "Garde les threads de chaque app sur un même CCD tant que ce CCD a un cœur libre, pour qu'ils partagent son cache L3 au lieu de traverser l'Infinity Fabric. Les threads qui s'échangent des données y gagnent : un pool de workers Node a tourné environ 12 % plus vite sur un 5900XT. Le travail qui occupe tous les cœurs reste réparti sur les deux CCD, à la même vitesse. Nécessite AMDCCDScheduler.kext.",
        statusActive: "Actif",
        statusOff: "Désactivé",
        statusLegacy: "Mode comparaison (0.1.0 : nouveaux threads seulement)",
        statusNotRun: "Chargé, en attente de Lilu",
        statusSymbolMissing: "Non installé : symboles du noyau manquants",
        statusLayoutMismatch: "Non installé : ce noyau macOS n'est pas encore pris en charge",
        statusRouteFailed: "Non installé : Lilu n'a pas pu intercepter le planificateur",
        statusSingleL3: "Inutile : ce processeur n'a qu'un cache L3",
        statusUnknown: "État inconnu",
        toggle: "Garder les threads de chaque app sur un CCD",
        toggleNote: "Jusqu'au redémarrage. Ajoutez ccdmode=0 aux boot-args pour démarrer désactivé.",
        statNew: "Placements examinés",
        statKept: "Ramenés sur le CCD de leur app",
        statSame: "Déjà sur le CCD de leur app",
        statFirst: "Apps avec un CCD attribué",
        statFull: "Laissés à macOS : CCD occupé",
        ccdCount: "%d CCD, chacun avec son cache L3",
        notLoadedHint: "Ce processeur a %d CCD. AMDCCDScheduler.kext garde les threads de chaque app sur l'un d'eux ; ajoutez-le dans OpenCore après Lilu.",
        adminPrompt: "RyzenStatus a besoin de votre mot de passe pour modifier le planificateur de CCD.",
        toggleFailed: "Le mode n'a pas été modifié.",
        logTitle: "Journal du kext"
    )

    static let it = CCDSchedulerStrings(
        header: "Scheduler dei CCD",
        footer: "Tiene i thread di ogni app su uno stesso CCD finché quel CCD ha un core libero, così condividono la sua cache L3 invece di attraversare l'Infinity Fabric. Ci guadagnano i thread che si passano dati: un pool di worker Node è stato circa il 12% più veloce su un 5900XT. Il lavoro che occupa tutti i core resta distribuito sui due CCD, alla stessa velocità. Richiede AMDCCDScheduler.kext.",
        statusActive: "Attivo",
        statusOff: "Disattivato",
        statusLegacy: "Modalità confronto (0.1.0: solo thread nuovi)",
        statusNotRun: "Caricato, in attesa di Lilu",
        statusSymbolMissing: "Non installato: mancano simboli del kernel",
        statusLayoutMismatch: "Non installato: questo kernel di macOS non è ancora supportato",
        statusRouteFailed: "Non installato: Lilu non è riuscito ad agganciare lo scheduler",
        statusSingleL3: "Non serve: questa CPU ha una sola cache L3",
        statusUnknown: "Stato sconosciuto",
        toggle: "Tieni i thread di ogni app su un CCD",
        toggleNote: "Fino al riavvio. Aggiungi ccdmode=0 ai boot-args per avviarlo disattivato.",
        statNew: "Posizionamenti esaminati",
        statKept: "Portati sul CCD della loro app",
        statSame: "Già sul CCD della loro app",
        statFirst: "App con un CCD assegnato",
        statFull: "Lasciati a macOS: CCD occupato",
        ccdCount: "%d CCD, ognuno con la sua cache L3",
        notLoadedHint: "Questa CPU ha %d CCD. AMDCCDScheduler.kext tiene i thread di ogni app su uno di essi; aggiungilo in OpenCore dopo Lilu.",
        adminPrompt: "RyzenStatus ha bisogno della tua password per cambiare lo scheduler dei CCD.",
        toggleFailed: "La modalità non è stata cambiata.",
        logTitle: "Log del kext"
    )

    static let ru = CCDSchedulerStrings(
        header: "Планировщик CCD",
        footer: "Держит потоки каждого приложения на одном CCD, пока у этого CCD есть свободное ядро, чтобы они делили его кэш L3, а не ходили через Infinity Fabric. Выигрывают потоки, которые передают друг другу данные: пул воркеров Node на 5900XT работал примерно на 12% быстрее. Работа, занимающая все ядра, по-прежнему распределяется по обоим CCD с той же скоростью. Нужен AMDCCDScheduler.kext.",
        statusActive: "Включён",
        statusOff: "Выключен",
        statusLegacy: "Режим сравнения (0.1.0: только новые потоки)",
        statusNotRun: "Загружен, ждёт Lilu",
        statusSymbolMissing: "Не установлен: нет символов ядра",
        statusLayoutMismatch: "Не установлен: это ядро macOS пока не поддерживается",
        statusRouteFailed: "Не установлен: Lilu не смог перехватить планировщик",
        statusSingleL3: "Не нужен: у этого процессора один кэш L3",
        statusUnknown: "Неизвестное состояние",
        toggle: "Держать потоки каждого приложения на одном CCD",
        toggleNote: "До перезагрузки. Добавьте ccdmode=0 в boot-args, чтобы он запускался выключенным.",
        statNew: "Проверено размещений",
        statKept: "Перенесены на CCD своего приложения",
        statSame: "Уже были на CCD своего приложения",
        statFirst: "Приложений с назначенным CCD",
        statFull: "Оставлены macOS: CCD занят",
        ccdCount: "CCD: %d, у каждого свой кэш L3",
        notLoadedHint: "У этого процессора CCD: %d. AMDCCDScheduler.kext держит потоки каждого приложения на одном из них; добавьте его в OpenCore после Lilu.",
        adminPrompt: "RyzenStatus нужен ваш пароль, чтобы изменить планировщик CCD.",
        toggleFailed: "Режим не изменён.",
        logTitle: "Журнал kext"
    )

    static let tr = CCDSchedulerStrings(
        header: "CCD zamanlayıcı",
        footer: "Her uygulamanın iş parçacıklarını, o CCD'de boş bir çekirdek olduğu sürece tek bir CCD'de tutar; böylece Infinity Fabric'i geçmek yerine onun L3 önbelleğini paylaşırlar. Birbirine veri aktaran iş parçacıkları kazanır: bir Node worker havuzu 5900XT'de yaklaşık %12 daha hızlı çalıştı. Tüm çekirdekleri dolduran işler yine iki CCD'ye aynı hızla dağılır. AMDCCDScheduler.kext gerekir.",
        statusActive: "Etkin",
        statusOff: "Kapalı",
        statusLegacy: "Karşılaştırma modu (0.1.0: yalnızca yeni iş parçacıkları)",
        statusNotRun: "Yüklendi, Lilu bekleniyor",
        statusSymbolMissing: "Kurulmadı: çekirdek sembolleri eksik",
        statusLayoutMismatch: "Kurulmadı: bu macOS çekirdeği henüz desteklenmiyor",
        statusRouteFailed: "Kurulmadı: Lilu zamanlayıcıya bağlanamadı",
        statusSingleL3: "Gerekmez: bu işlemcide tek bir L3 önbelleği var",
        statusUnknown: "Bilinmeyen durum",
        toggle: "Her uygulamanın iş parçacıklarını tek CCD'de tut",
        toggleNote: "Yeniden başlatmaya kadar. Kapalı başlaması için boot-args'a ccdmode=0 ekleyin.",
        statNew: "İncelenen yerleştirmeler",
        statKept: "Uygulamasının CCD'sine taşınan",
        statSame: "Zaten uygulamasının CCD'sinde",
        statFirst: "CCD atanan uygulamalar",
        statFull: "macOS'a bırakılan: CCD dolu",
        ccdCount: "%d CCD, her birinin kendi L3 önbelleği",
        notLoadedHint: "Bu işlemcide %d CCD var. AMDCCDScheduler.kext her uygulamanın iş parçacıklarını bunlardan birinde tutar; OpenCore'da Lilu'dan sonra ekleyin.",
        adminPrompt: "RyzenStatus'un CCD zamanlayıcıyı değiştirmek için parolanıza ihtiyacı var.",
        toggleFailed: "Mod değiştirilmedi.",
        logTitle: "Kext günlüğü"
    )

    static let ja = CCDSchedulerStrings(
        header: "CCD スケジューラ",
        footer: "CCD に空きコアがある間、各アプリのスレッドをその CCD に置き、Infinity Fabric を越える代わりに L3 キャッシュを共有させます。互いにデータを渡すスレッドで効果があり、5900XT では Node のワーカープールが約 12% 速くなりました。全コアを使う処理はこれまでどおり両方の CCD に分散し、速度も変わりません。AMDCCDScheduler.kext が必要です。",
        statusActive: "有効",
        statusOff: "オフ",
        statusLegacy: "比較モード（0.1.0：新しいスレッドのみ）",
        statusNotRun: "読み込み済み、Lilu を待機中",
        statusSymbolMissing: "未インストール：カーネルシンボルがありません",
        statusLayoutMismatch: "未インストール：この macOS カーネルはまだ未対応です",
        statusRouteFailed: "未インストール：Lilu がスケジューラをフックできませんでした",
        statusSingleL3: "不要：この CPU の L3 キャッシュは 1 つです",
        statusUnknown: "不明な状態",
        toggle: "各アプリのスレッドを 1 つの CCD に置く",
        toggleNote: "再起動まで有効です。オフで起動するには boot-args に ccdmode=0 を追加します。",
        statNew: "確認した配置",
        statKept: "アプリの CCD に移動",
        statSame: "すでにアプリの CCD 上",
        statFirst: "CCD を割り当てたアプリ",
        statFull: "macOS に任せた（CCD が使用中）",
        ccdCount: "CCD %d 個（それぞれに L3 キャッシュ）",
        notLoadedHint: "この CPU には CCD が %d 個あります。AMDCCDScheduler.kext は各アプリのスレッドをそのうち 1 つに置きます。OpenCore で Lilu の後に追加してください。",
        adminPrompt: "CCD スケジューラを変更するには RyzenStatus にパスワードが必要です。",
        toggleFailed: "モードは変更されませんでした。",
        logTitle: "kext のログ"
    )

    static let ko = CCDSchedulerStrings(
        header: "CCD 스케줄러",
        footer: "CCD에 빈 코어가 있는 동안 각 앱의 스레드를 그 CCD에 두어, Infinity Fabric을 건너는 대신 L3 캐시를 함께 쓰게 합니다. 서로 데이터를 주고받는 스레드가 빨라집니다. 5900XT에서 Node 워커 풀이 약 12% 빨라졌습니다. 모든 코어를 채우는 작업은 지금처럼 두 CCD에 나뉘며 속도도 같습니다. AMDCCDScheduler.kext가 필요합니다.",
        statusActive: "활성",
        statusOff: "꺼짐",
        statusLegacy: "비교 모드(0.1.0: 새 스레드만)",
        statusNotRun: "로드됨, Lilu 대기 중",
        statusSymbolMissing: "설치 안 됨: 커널 심볼 없음",
        statusLayoutMismatch: "설치 안 됨: 이 macOS 커널은 아직 지원되지 않음",
        statusRouteFailed: "설치 안 됨: Lilu가 스케줄러를 후킹하지 못함",
        statusSingleL3: "필요 없음: 이 CPU는 L3 캐시가 하나뿐임",
        statusUnknown: "알 수 없는 상태",
        toggle: "각 앱의 스레드를 한 CCD에 유지",
        toggleNote: "재시동할 때까지 유지됩니다. 꺼진 상태로 시작하려면 boot-args에 ccdmode=0을 추가하세요.",
        statNew: "확인한 배치",
        statKept: "앱의 CCD로 옮김",
        statSame: "이미 앱의 CCD에 있음",
        statFirst: "CCD가 지정된 앱",
        statFull: "macOS에 맡김: CCD 사용 중",
        ccdCount: "CCD %d개, 각각 L3 캐시 보유",
        notLoadedHint: "이 CPU에는 CCD가 %d개 있습니다. AMDCCDScheduler.kext는 각 앱의 스레드를 그중 하나에 둡니다. OpenCore에서 Lilu 다음에 추가하세요.",
        adminPrompt: "CCD 스케줄러를 변경하려면 RyzenStatus에 암호가 필요합니다.",
        toggleFailed: "모드가 변경되지 않았습니다.",
        logTitle: "kext 로그"
    )

    static let zhHans = CCDSchedulerStrings(
        header: "CCD 调度器",
        footer: "在 CCD 还有空闲核心时，让每个应用的线程留在这个 CCD 上，共享它的 L3 缓存，而不是跨越 Infinity Fabric。互相传递数据的线程会受益：在 5900XT 上，一个 Node worker 池快了约 12%。占满所有核心的工作仍会分布在两个 CCD 上，速度不变。需要 AMDCCDScheduler.kext。",
        statusActive: "已启用",
        statusOff: "已关闭",
        statusLegacy: "对比模式（0.1.0：仅新线程）",
        statusNotRun: "已加载，等待 Lilu",
        statusSymbolMissing: "未安装：缺少内核符号",
        statusLayoutMismatch: "未安装：尚不支持此 macOS 内核",
        statusRouteFailed: "未安装：Lilu 无法挂钩调度器",
        statusSingleL3: "无需：此 CPU 只有一个 L3 缓存",
        statusUnknown: "未知状态",
        toggle: "让每个应用的线程留在一个 CCD 上",
        toggleNote: "重启前有效。在 boot-args 中加入 ccdmode=0 可让它以关闭状态启动。",
        statNew: "已检查的放置",
        statKept: "移到所属应用的 CCD",
        statSame: "已在所属应用的 CCD 上",
        statFirst: "已分配 CCD 的应用",
        statFull: "交给 macOS：CCD 繁忙",
        ccdCount: "%d 个 CCD，各有一个 L3 缓存",
        notLoadedHint: "此 CPU 有 %d 个 CCD。AMDCCDScheduler.kext 会让每个应用的线程留在其中一个上；请在 OpenCore 中将它加在 Lilu 之后。",
        adminPrompt: "RyzenStatus 需要你的密码来更改 CCD 调度器。",
        toggleFailed: "模式未更改。",
        logTitle: "kext 日志"
    )

    static let zhTW = CCDSchedulerStrings(
        header: "CCD 排程器",
        footer: "在 CCD 還有空閒核心時，讓每個 App 的執行緒留在這個 CCD 上，共用它的 L3 快取，而不是跨越 Infinity Fabric。互相傳遞資料的執行緒會受益：在 5900XT 上，一個 Node worker 池快了約 12%。佔滿所有核心的工作仍會分散在兩個 CCD 上，速度不變。需要 AMDCCDScheduler.kext。",
        statusActive: "已啟用",
        statusOff: "已關閉",
        statusLegacy: "比較模式（0.1.0：僅新執行緒）",
        statusNotRun: "已載入，等待 Lilu",
        statusSymbolMissing: "未安裝：缺少核心符號",
        statusLayoutMismatch: "未安裝：尚不支援此 macOS 核心",
        statusRouteFailed: "未安裝：Lilu 無法掛鉤排程器",
        statusSingleL3: "不需要：此 CPU 只有一個 L3 快取",
        statusUnknown: "未知狀態",
        toggle: "讓每個 App 的執行緒留在一個 CCD 上",
        toggleNote: "重新開機前有效。在 boot-args 加入 ccdmode=0 可讓它以關閉狀態啟動。",
        statNew: "已檢查的配置",
        statKept: "移到所屬 App 的 CCD",
        statSame: "已在所屬 App 的 CCD 上",
        statFirst: "已指定 CCD 的 App",
        statFull: "交給 macOS：CCD 忙碌",
        ccdCount: "%d 個 CCD，各有一個 L3 快取",
        notLoadedHint: "此 CPU 有 %d 個 CCD。AMDCCDScheduler.kext 會讓每個 App 的執行緒留在其中一個上；請在 OpenCore 中將它加在 Lilu 之後。",
        adminPrompt: "RyzenStatus 需要你的密碼來變更 CCD 排程器。",
        toggleFailed: "模式未變更。",
        logTitle: "kext 記錄"
    )

    static let zhHK = CCDSchedulerStrings(
        header: "CCD 排程器",
        footer: "喺 CCD 仲有空閒核心嘅時候，讓每個 App 嘅執行緒留喺呢個 CCD 上，共用佢嘅 L3 快取，而唔係跨過 Infinity Fabric。互相傳資料嘅執行緒會受惠：喺 5900XT 上，一個 Node worker 池快咗大約 12%。用滿所有核心嘅工作仍然會分散喺兩個 CCD 上，速度唔變。需要 AMDCCDScheduler.kext。",
        statusActive: "已啟用",
        statusOff: "已關閉",
        statusLegacy: "比較模式（0.1.0：只限新執行緒）",
        statusNotRun: "已載入，等緊 Lilu",
        statusSymbolMissing: "未安裝：缺少核心符號",
        statusLayoutMismatch: "未安裝：仲未支援呢個 macOS 核心",
        statusRouteFailed: "未安裝：Lilu 無法掛鈎排程器",
        statusSingleL3: "唔需要：呢部 CPU 只有一個 L3 快取",
        statusUnknown: "未知狀態",
        toggle: "讓每個 App 嘅執行緒留喺一個 CCD 上",
        toggleNote: "重新開機前有效。喺 boot-args 加入 ccdmode=0 可以令佢以關閉狀態啟動。",
        statNew: "已檢查嘅配置",
        statKept: "移去所屬 App 嘅 CCD",
        statSame: "已經喺所屬 App 嘅 CCD 上",
        statFirst: "已指定 CCD 嘅 App",
        statFull: "交俾 macOS：CCD 忙緊",
        ccdCount: "%d 個 CCD，各有一個 L3 快取",
        notLoadedHint: "呢部 CPU 有 %d 個 CCD。AMDCCDScheduler.kext 會讓每個 App 嘅執行緒留喺其中一個上；請喺 OpenCore 將佢加喺 Lilu 之後。",
        adminPrompt: "RyzenStatus 需要你嘅密碼嚟更改 CCD 排程器。",
        toggleFailed: "模式未有更改。",
        logTitle: "kext 記錄"
    )

    static let sk = CCDSchedulerStrings(
        header: "Plánovač CCD",
        footer: "Drží vlákna každej aplikácie na jednom CCD, kým má tento CCD voľné jadro, aby zdieľali jeho vyrovnávaciu pamäť L3 namiesto prechodu cez Infinity Fabric. Získajú vlákna, ktoré si navzájom odovzdávajú dáta: skupina workerov Node bežala na 5900XT asi o 12 % rýchlejšie. Práca, ktorá vyťaží všetky jadrá, sa naďalej rozdeľuje na oba CCD rovnakou rýchlosťou. Vyžaduje AMDCCDScheduler.kext.",
        statusActive: "Aktívny",
        statusOff: "Vypnutý",
        statusLegacy: "Porovnávací režim (0.1.0: len nové vlákna)",
        statusNotRun: "Načítaný, čaká na Lilu",
        statusSymbolMissing: "Nenainštalovaný: chýbajú symboly jadra",
        statusLayoutMismatch: "Nenainštalovaný: toto jadro macOS zatiaľ nie je podporované",
        statusRouteFailed: "Nenainštalovaný: Lilu nedokázal zachytiť plánovač",
        statusSingleL3: "Netreba: tento procesor má jednu vyrovnávaciu pamäť L3",
        statusUnknown: "Neznámy stav",
        toggle: "Držať vlákna každej aplikácie na jednom CCD",
        toggleNote: "Do reštartu. Pridajte ccdmode=0 do boot-args, aby sa spúšťal vypnutý.",
        statNew: "Skontrolované umiestnenia",
        statKept: "Presunuté na CCD svojej aplikácie",
        statSame: "Už boli na CCD svojej aplikácie",
        statFirst: "Aplikácie s prideleným CCD",
        statFull: "Ponechané na macOS: CCD obsadený",
        ccdCount: "Počet CCD: %d, každý s vlastnou L3",
        notLoadedHint: "Tento procesor má %d CCD. AMDCCDScheduler.kext drží vlákna každej aplikácie na jednom z nich; pridajte ho v OpenCore za Lilu.",
        adminPrompt: "RyzenStatus potrebuje vaše heslo na zmenu plánovača CCD.",
        toggleFailed: "Režim sa nezmenil.",
        logTitle: "Záznam kextu"
    )

    static let uk = CCDSchedulerStrings(
        header: "Планувальник CCD",
        footer: "Тримає потоки кожного застосунку на одному CCD, поки цей CCD має вільне ядро, щоб вони ділили його кеш L3, а не ходили через Infinity Fabric. Виграють потоки, що передають одне одному дані: пул воркерів Node на 5900XT працював приблизно на 12% швидше. Робота, що займає всі ядра, як і раніше розподіляється на обидва CCD з тією самою швидкістю. Потрібен AMDCCDScheduler.kext.",
        statusActive: "Увімкнено",
        statusOff: "Вимкнено",
        statusLegacy: "Режим порівняння (0.1.0: лише нові потоки)",
        statusNotRun: "Завантажено, чекає на Lilu",
        statusSymbolMissing: "Не встановлено: бракує символів ядра",
        statusLayoutMismatch: "Не встановлено: це ядро macOS ще не підтримується",
        statusRouteFailed: "Не встановлено: Lilu не зміг перехопити планувальник",
        statusSingleL3: "Не потрібно: цей процесор має один кеш L3",
        statusUnknown: "Невідомий стан",
        toggle: "Тримати потоки кожного застосунку на одному CCD",
        toggleNote: "До перезавантаження. Додайте ccdmode=0 до boot-args, щоб він запускався вимкненим.",
        statNew: "Перевірено розміщень",
        statKept: "Перенесені на CCD свого застосунку",
        statSame: "Уже були на CCD свого застосунку",
        statFirst: "Застосунків із призначеним CCD",
        statFull: "Залишені macOS: CCD зайнятий",
        ccdCount: "CCD: %d, у кожного свій кеш L3",
        notLoadedHint: "Цей процесор має CCD: %d. AMDCCDScheduler.kext тримає потоки кожного застосунку на одному з них; додайте його в OpenCore після Lilu.",
        adminPrompt: "RyzenStatus потрібен ваш пароль, щоб змінити планувальник CCD.",
        toggleFailed: "Режим не змінено.",
        logTitle: "Журнал kext"
    )
}
