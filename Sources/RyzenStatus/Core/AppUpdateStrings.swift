// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

struct AppUpdateStrings {
    let pageTitle: String
    let hubDescription: String
    let caption: String
    let panelCaption: String
    let checkNow: String
    let checking: String
    let lastCheckFormat: String
    let neverChecked: String
    let upToDate: String
    let coverageNote: String
    let selectAll: String
    let clearSelection: String
    let updateSelectedFormat: String
    let updateOne: String
    let openAppStore: String
    let appStoreBadge: String
    let storeHint: String
    let frequencyLabel: String
    let frequencyOff: String
    let frequencyDaily: String
    let frequencyWeekly: String
    let nextCheckFormat: String
    let notifyToggle: String
    let includeStoreToggle: String
    let includeStoreCaption: String
    let packageMissing: String
    let notificationBodyFormat: String
    let notificationBodyOne: String
    let showInPanel: String
}

extension FeatureStrings {
    static func appUpdates(_ language: AppLanguage) -> AppUpdateStrings {
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
        }
    }
}

extension AppUpdateStrings {
    static let enUS = AppUpdateStrings(
        pageTitle: "App updates",
        hubDescription: "Find and install updates for the apps you have",
        caption: "Looks for a newer version of the apps on this Mac and updates the ones you pick, so you do not have to open a store for each one.",
        panelCaption: "See which apps have a newer version",
        checkNow: "Check now",
        checking: "Checking",
        lastCheckFormat: "Last checked %@",
        neverChecked: "Not checked yet",
        upToDate: "Every app is up to date",
        coverageNote: "Covers apps installed with Homebrew and apps from the App Store. Apps that carry their own updater keep updating themselves.",
        selectAll: "Select all",
        clearSelection: "Clear",
        updateSelectedFormat: "Update %d",
        updateOne: "Update",
        openAppStore: "Open the App Store",
        appStoreBadge: "App Store",
        storeHint: "Opens the App Store, where this update is installed",
        frequencyLabel: "Check in the background",
        frequencyOff: "Off",
        frequencyDaily: "Every day",
        frequencyWeekly: "Every week",
        nextCheckFormat: "Next check %@",
        notifyToggle: "Tell me when an app has an update",
        includeStoreToggle: "Include apps from the App Store",
        includeStoreCaption: "Asks Apple which version is current for the apps you got from the store. Turn it off to keep every check on this Mac.",
        packageMissing: "Homebrew is not installed, so apps cannot be updated from here yet.",
        notificationBodyFormat: "%@ apps have a newer version.",
        notificationBodyOne: "One app has a newer version.",
        showInPanel: "Show in panel"
    )

    static let ptBR = AppUpdateStrings(
        pageTitle: "Atualizações de apps",
        hubDescription: "Encontre e instale atualizações dos seus apps",
        caption: "Procura versão nova dos apps deste Mac e atualiza os que você escolher, sem precisar abrir uma loja para cada um.",
        panelCaption: "Veja quais apps têm versão nova",
        checkNow: "Verificar agora",
        checking: "Verificando",
        lastCheckFormat: "Última verificação %@",
        neverChecked: "Ainda não verificado",
        upToDate: "Todos os apps estão em dia",
        coverageNote: "Cobre apps instalados pelo Homebrew e apps da App Store. Apps com atualizador próprio continuam se atualizando sozinhos.",
        selectAll: "Selecionar tudo",
        clearSelection: "Limpar",
        updateSelectedFormat: "Atualizar %d",
        updateOne: "Atualizar",
        openAppStore: "Abrir a App Store",
        appStoreBadge: "App Store",
        storeHint: "Abre a App Store, onde essa atualização é instalada",
        frequencyLabel: "Verificar em segundo plano",
        frequencyOff: "Desligado",
        frequencyDaily: "Todo dia",
        frequencyWeekly: "Toda semana",
        nextCheckFormat: "Próxima verificação %@",
        notifyToggle: "Avisar quando um app tiver atualização",
        includeStoreToggle: "Incluir apps da App Store",
        includeStoreCaption: "Pergunta à Apple qual é a versão atual dos apps que você baixou da loja. Desligue para deixar toda a verificação neste Mac.",
        packageMissing: "O Homebrew não está instalado, então ainda não dá para atualizar apps por aqui.",
        notificationBodyFormat: "%@ apps têm versão nova.",
        notificationBodyOne: "Um app tem versão nova.",
        showInPanel: "Mostrar no painel"
    )

    static let es = AppUpdateStrings(
        pageTitle: "Actualizaciones de apps",
        hubDescription: "Encuentra e instala actualizaciones de tus apps",
        caption: "Busca una versión más nueva de las apps de este Mac y actualiza las que elijas, sin abrir una tienda para cada una.",
        panelCaption: "Mira qué apps tienen una versión más nueva",
        checkNow: "Buscar ahora",
        checking: "Buscando",
        lastCheckFormat: "Última búsqueda %@",
        neverChecked: "Todavía sin buscar",
        upToDate: "Todas las apps están al día",
        coverageNote: "Cubre las apps instaladas con Homebrew y las apps de la App Store. Las apps con su propio actualizador siguen actualizándose solas.",
        selectAll: "Seleccionar todo",
        clearSelection: "Limpiar",
        updateSelectedFormat: "Actualizar %d",
        updateOne: "Actualizar",
        openAppStore: "Abrir la App Store",
        appStoreBadge: "App Store",
        storeHint: "Abre la App Store, donde se instala esta actualización",
        frequencyLabel: "Buscar en segundo plano",
        frequencyOff: "Desactivado",
        frequencyDaily: "Cada día",
        frequencyWeekly: "Cada semana",
        nextCheckFormat: "Próxima búsqueda %@",
        notifyToggle: "Avisarme cuando una app tenga actualización",
        includeStoreToggle: "Incluir apps de la App Store",
        includeStoreCaption: "Pregunta a Apple cuál es la versión actual de las apps que obtuviste en la tienda. Desactívalo para que toda la búsqueda quede en este Mac.",
        packageMissing: "Homebrew no está instalado, así que todavía no se pueden actualizar apps desde aquí.",
        notificationBodyFormat: "%@ apps tienen una versión más nueva.",
        notificationBodyOne: "Una app tiene una versión más nueva.",
        showInPanel: "Mostrar en el panel"
    )

    static let de = AppUpdateStrings(
        pageTitle: "App-Updates",
        hubDescription: "Updates für deine Apps finden und installieren",
        caption: "Sucht nach neueren Versionen der Apps auf diesem Mac und aktualisiert die, die du auswählst, ohne für jede einen Store zu öffnen.",
        panelCaption: "Sieh, welche Apps eine neuere Version haben",
        checkNow: "Jetzt prüfen",
        checking: "Wird geprüft",
        lastCheckFormat: "Zuletzt geprüft %@",
        neverChecked: "Noch nicht geprüft",
        upToDate: "Alle Apps sind aktuell",
        coverageNote: "Deckt Apps ab, die mit Homebrew installiert wurden, und Apps aus dem App Store. Apps mit eigenem Updater aktualisieren sich weiterhin selbst.",
        selectAll: "Alle auswählen",
        clearSelection: "Aufheben",
        updateSelectedFormat: "%d aktualisieren",
        updateOne: "Aktualisieren",
        openAppStore: "App Store öffnen",
        appStoreBadge: "App Store",
        storeHint: "Öffnet den App Store, wo dieses Update installiert wird",
        frequencyLabel: "Im Hintergrund prüfen",
        frequencyOff: "Aus",
        frequencyDaily: "Jeden Tag",
        frequencyWeekly: "Jede Woche",
        nextCheckFormat: "Nächste Prüfung %@",
        notifyToggle: "Bescheid geben, wenn eine App ein Update hat",
        includeStoreToggle: "Apps aus dem App Store einbeziehen",
        includeStoreCaption: "Fragt Apple nach der aktuellen Version der Apps, die du im Store geholt hast. Schalte es aus, damit jede Prüfung auf diesem Mac bleibt.",
        packageMissing: "Homebrew ist nicht installiert, deshalb lassen sich Apps von hier noch nicht aktualisieren.",
        notificationBodyFormat: "%@ Apps haben eine neuere Version.",
        notificationBodyOne: "Eine App hat eine neuere Version.",
        showInPanel: "Im Panel anzeigen"
    )

    static let fr = AppUpdateStrings(
        pageTitle: "Mises à jour des apps",
        hubDescription: "Trouvez et installez les mises à jour de vos apps",
        caption: "Cherche une version plus récente des apps de ce Mac et met à jour celles que vous choisissez, sans ouvrir une boutique pour chacune.",
        panelCaption: "Voyez quelles apps ont une version plus récente",
        checkNow: "Vérifier maintenant",
        checking: "Vérification",
        lastCheckFormat: "Dernière vérification %@",
        neverChecked: "Pas encore vérifié",
        upToDate: "Toutes les apps sont à jour",
        coverageNote: "Couvre les apps installées avec Homebrew et les apps de l'App Store. Les apps qui ont leur propre outil de mise à jour continuent de se mettre à jour seules.",
        selectAll: "Tout sélectionner",
        clearSelection: "Effacer",
        updateSelectedFormat: "Mettre à jour %d",
        updateOne: "Mettre à jour",
        openAppStore: "Ouvrir l'App Store",
        appStoreBadge: "App Store",
        storeHint: "Ouvre l'App Store, où cette mise à jour s'installe",
        frequencyLabel: "Vérifier en arrière-plan",
        frequencyOff: "Désactivé",
        frequencyDaily: "Chaque jour",
        frequencyWeekly: "Chaque semaine",
        nextCheckFormat: "Prochaine vérification %@",
        notifyToggle: "Me prévenir quand une app a une mise à jour",
        includeStoreToggle: "Inclure les apps de l'App Store",
        includeStoreCaption: "Demande à Apple la version actuelle des apps obtenues dans la boutique. Désactivez pour que toute la vérification reste sur ce Mac.",
        packageMissing: "Homebrew n'est pas installé, les apps ne peuvent donc pas encore être mises à jour d'ici.",
        notificationBodyFormat: "%@ apps ont une version plus récente.",
        notificationBodyOne: "Une app a une version plus récente.",
        showInPanel: "Afficher dans le panneau"
    )

    static let it = AppUpdateStrings(
        pageTitle: "Aggiornamenti delle app",
        hubDescription: "Trova e installa gli aggiornamenti delle tue app",
        caption: "Cerca una versione più recente delle app di questo Mac e aggiorna quelle che scegli, senza aprire un negozio per ognuna.",
        panelCaption: "Guarda quali app hanno una versione più recente",
        checkNow: "Controlla ora",
        checking: "Controllo in corso",
        lastCheckFormat: "Ultimo controllo %@",
        neverChecked: "Non ancora controllato",
        upToDate: "Tutte le app sono aggiornate",
        coverageNote: "Copre le app installate con Homebrew e le app dell'App Store. Le app con un aggiornatore proprio continuano ad aggiornarsi da sole.",
        selectAll: "Seleziona tutto",
        clearSelection: "Azzera",
        updateSelectedFormat: "Aggiorna %d",
        updateOne: "Aggiorna",
        openAppStore: "Apri l'App Store",
        appStoreBadge: "App Store",
        storeHint: "Apre l'App Store, dove questo aggiornamento viene installato",
        frequencyLabel: "Controlla in background",
        frequencyOff: "Off",
        frequencyDaily: "Ogni giorno",
        frequencyWeekly: "Ogni settimana",
        nextCheckFormat: "Prossimo controllo %@",
        notifyToggle: "Avvisami quando un'app ha un aggiornamento",
        includeStoreToggle: "Includi le app dell'App Store",
        includeStoreCaption: "Chiede ad Apple qual è la versione attuale delle app prese dal negozio. Disattivalo per tenere ogni controllo su questo Mac.",
        packageMissing: "Homebrew non è installato, quindi da qui non si possono ancora aggiornare le app.",
        notificationBodyFormat: "%@ app hanno una versione più recente.",
        notificationBodyOne: "Un'app ha una versione più recente.",
        showInPanel: "Mostra nel pannello"
    )

    static let ja = AppUpdateStrings(
        pageTitle: "Appのアップデート",
        hubDescription: "使っているAppのアップデートを見つけて適用",
        caption: "このMacのAppに新しいバージョンがないか調べ、選んだものだけをアップデートします。App ごとにストアを開く必要はありません。",
        panelCaption: "新しいバージョンがあるAppを確認",
        checkNow: "今すぐ確認",
        checking: "確認中",
        lastCheckFormat: "前回の確認 %@",
        neverChecked: "まだ確認していません",
        upToDate: "すべてのAppが最新です",
        coverageNote: "Homebrewで入れたAppとApp StoreのAppが対象です。独自のアップデート機能を持つAppは、これまでどおり自分で更新します。",
        selectAll: "すべて選択",
        clearSelection: "選択解除",
        updateSelectedFormat: "%d件をアップデート",
        updateOne: "アップデート",
        openAppStore: "App Storeを開く",
        appStoreBadge: "App Store",
        storeHint: "このアップデートを適用するApp Storeを開きます",
        frequencyLabel: "バックグラウンドで確認",
        frequencyOff: "オフ",
        frequencyDaily: "毎日",
        frequencyWeekly: "毎週",
        nextCheckFormat: "次回の確認 %@",
        notifyToggle: "アップデートがあるときに知らせる",
        includeStoreToggle: "App StoreのAppも含める",
        includeStoreCaption: "ストアで入手したAppの最新バージョンをAppleに問い合わせます。オフにすると、確認はすべてこのMacの中だけで行われます。",
        packageMissing: "Homebrewが入っていないため、ここからAppをアップデートすることはまだできません。",
        notificationBodyFormat: "%@件のAppに新しいバージョンがあります。",
        notificationBodyOne: "1件のAppに新しいバージョンがあります。",
        showInPanel: "パネルに表示"
    )

    static let zhHans = AppUpdateStrings(
        pageTitle: "App 更新",
        hubDescription: "发现并安装你所用 App 的更新",
        caption: "查找这台 Mac 上 App 的更新版本，并更新你选中的 App，无需为每个 App 打开商店。",
        panelCaption: "查看哪些 App 有更新版本",
        checkNow: "立即检查",
        checking: "正在检查",
        lastCheckFormat: "上次检查 %@",
        neverChecked: "尚未检查过",
        upToDate: "所有 App 都已是最新",
        coverageNote: "涵盖通过 Homebrew 安装的 App 和来自 App Store 的 App。带有自有更新器的 App 将继续自行更新。",
        selectAll: "全选",
        clearSelection: "清除",
        updateSelectedFormat: "更新 %d 个",
        updateOne: "更新",
        openAppStore: "打开 App Store",
        appStoreBadge: "App Store",
        storeHint: "打开 App Store，此更新将在其中安装",
        frequencyLabel: "后台检查",
        frequencyOff: "关闭",
        frequencyDaily: "每天",
        frequencyWeekly: "每周",
        nextCheckFormat: "下次检查 %@",
        notifyToggle: "当 App 有更新时通知我",
        includeStoreToggle: "包含来自 App Store 的 App",
        includeStoreCaption: "向 Apple 查询你从商店获取的 App 的当前版本。关闭后所有检查将仅在这台 Mac 上进行。",
        packageMissing: "Homebrew 未安装，因此尚无法从此处更新 App。",
        notificationBodyFormat: "%@ 个 App 有较新版本。",
        notificationBodyOne: "有一个 App 有较新版本。",
        showInPanel: "在面板中显示"
    )

    static let zhTW = AppUpdateStrings(
        pageTitle: "App 更新",
        hubDescription: "找出並安裝你所用 App 的更新",
        caption: "尋找這部 Mac 上 App 的較新版本，並更新你所選的 App，無需為每個 App 開啟商店。",
        panelCaption: "查看哪些 App 有較新版本",
        checkNow: "立即檢查",
        checking: "正在檢查",
        lastCheckFormat: "上次檢查 %@",
        neverChecked: "尚未檢查",
        upToDate: "所有 App 都已是最新",
        coverageNote: "涵蓋透過 Homebrew 安裝的 App 與來自 App Store 的 App。帶有自有更新機制的 App 將繼續自行更新。",
        selectAll: "全選",
        clearSelection: "清除",
        updateSelectedFormat: "更新 %d 個",
        updateOne: "更新",
        openAppStore: "開啟 App Store",
        appStoreBadge: "App Store",
        storeHint: "開啟 App Store，在此安裝更新",
        frequencyLabel: "背景檢查",
        frequencyOff: "關閉",
        frequencyDaily: "每天",
        frequencyWeekly: "每週",
        nextCheckFormat: "下次檢查 %@",
        notifyToggle: "當 App 有更新時通知我",
        includeStoreToggle: "包含來自 App Store 的 App",
        includeStoreCaption: "向 Apple 查詢你從商店取得的 App 的目前版本。關閉後所有檢查將只在這部 Mac 上進行。",
        packageMissing: "尚未安裝 Homebrew，因此無法從此處更新 App。",
        notificationBodyFormat: "%@ 個 App 有較新版本。",
        notificationBodyOne: "有一個 App 有較新版本。",
        showInPanel: "在面板中顯示"
    )

    static let zhHK = AppUpdateStrings(
        pageTitle: "App 更新",
        hubDescription: "搵出並安裝你用到嘅 App 更新",
        caption: "搵呢部 Mac 上 App 嘅更新版本，並更新你揀嘅 App，唔使為每個 App 開商店。",
        panelCaption: "睇吓邊啲 App 有新版本",
        checkNow: "即刻檢查",
        checking: "檢查緊",
        lastCheckFormat: "上次檢查 %@",
        neverChecked: "未檢查過",
        upToDate: "所有 App 都係最新",
        coverageNote: "涵蓋透過 Homebrew 安裝嘅 App 同 App Store 嘅 App。自帶更新機制嘅 App 會繼續自己更新。",
        selectAll: "揀晒",
        clearSelection: "清除",
        updateSelectedFormat: "更新 %d 個",
        updateOne: "更新",
        openAppStore: "打開 App Store",
        appStoreBadge: "App Store",
        storeHint: "打開 App Store，呢個更新會喺嗰度安裝",
        frequencyLabel: "背景檢查",
        frequencyOff: "關",
        frequencyDaily: "每日",
        frequencyWeekly: "每星期",
        nextCheckFormat: "下次檢查 %@",
        notifyToggle: "當 App 有更新時通知我",
        includeStoreToggle: "包括 App Store 嘅 App",
        includeStoreCaption: "向 Apple 查詢你喺商店取得嘅 App 嘅目前版本。關閉後所有檢查淨係會喺呢部 Mac 上進行。",
        packageMissing: "Homebrew 未安裝，所以暫時冇得由呢度更新 App。",
        notificationBodyFormat: "%@ 個 App 有新版本。",
        notificationBodyOne: "有一個 App 有新版本。",
        showInPanel: "喺面板顯示"
    )

    static let tr = AppUpdateStrings(
        pageTitle: "Uygulama güncellemeleri",
        hubDescription: "Uygulamalarının güncellemelerini bul ve kur",
        caption: "Bu Mac'teki uygulamaların yeni sürümünü arar ve seçtiklerini günceller, böylece her biri için ayrı bir mağaza açman gerekmez.",
        panelCaption: "Hangi uygulamaların yeni sürümü olduğunu gör",
        checkNow: "Şimdi denetle",
        checking: "Denetleniyor",
        lastCheckFormat: "Son denetleme %@",
        neverChecked: "Henüz denetlenmedi",
        upToDate: "Tüm uygulamalar güncel",
        coverageNote: "Homebrew ile kurulan uygulamaları ve App Store uygulamalarını kapsar. Kendi güncelleyicisi olan uygulamalar kendini güncellemeye devam eder.",
        selectAll: "Tümünü seç",
        clearSelection: "Temizle",
        updateSelectedFormat: "%d güncelle",
        updateOne: "Güncelle",
        openAppStore: "App Store'u aç",
        appStoreBadge: "App Store",
        storeHint: "Bu güncellemenin kurulduğu App Store'u açar",
        frequencyLabel: "Arka planda denetle",
        frequencyOff: "Kapalı",
        frequencyDaily: "Her gün",
        frequencyWeekly: "Her hafta",
        nextCheckFormat: "Sonraki denetleme %@",
        notifyToggle: "Bir uygulamanın güncellemesi olduğunda haber ver",
        includeStoreToggle: "App Store uygulamalarını da kat",
        includeStoreCaption: "Mağazadan aldığın uygulamaların güncel sürümünü Apple'a sorar. Her denetlemeyi bu Mac'te tutmak için kapat.",
        packageMissing: "Homebrew kurulu değil, bu yüzden uygulamalar buradan henüz güncellenemiyor.",
        notificationBodyFormat: "%@ uygulamanın yeni sürümü var.",
        notificationBodyOne: "Bir uygulamanın yeni sürümü var.",
        showInPanel: "Panelde göster"
    )

    static let ru = AppUpdateStrings(
        pageTitle: "Обновления приложений",
        hubDescription: "Находите и устанавливайте обновления ваших приложений",
        caption: "Ищет новые версии приложений на этом Mac и обновляет те, что вы выберете, так что открывать магазин для каждого не нужно.",
        panelCaption: "Посмотрите, у каких приложений есть новая версия",
        checkNow: "Проверить сейчас",
        checking: "Проверка",
        lastCheckFormat: "Последняя проверка %@",
        neverChecked: "Ещё не проверялось",
        upToDate: "Все приложения обновлены",
        coverageNote: "Охватывает приложения, установленные через Homebrew, и приложения из App Store. Приложения со своим обновлятором продолжают обновляться сами.",
        selectAll: "Выбрать все",
        clearSelection: "Снять выбор",
        updateSelectedFormat: "Обновить: %d",
        updateOne: "Обновить",
        openAppStore: "Открыть App Store",
        appStoreBadge: "App Store",
        storeHint: "Открывает App Store, где устанавливается это обновление",
        frequencyLabel: "Проверять в фоне",
        frequencyOff: "Выключено",
        frequencyDaily: "Каждый день",
        frequencyWeekly: "Каждую неделю",
        nextCheckFormat: "Следующая проверка %@",
        notifyToggle: "Сообщать, когда у приложения есть обновление",
        includeStoreToggle: "Включать приложения из App Store",
        includeStoreCaption: "Спрашивает у Apple текущую версию приложений, купленных в магазине. Выключите, чтобы вся проверка оставалась на этом Mac.",
        packageMissing: "Homebrew не установлен, поэтому обновлять приложения отсюда пока нельзя.",
        notificationBodyFormat: "Приложений с новой версией: %@.",
        notificationBodyOne: "У одного приложения есть новая версия.",
        showInPanel: "Показывать в панели"
    )

    static let ko = AppUpdateStrings(
        pageTitle: "앱 업데이트",
        hubDescription: "사용 중인 앱의 업데이트를 찾아 설치",
        caption: "이 Mac에 있는 앱의 새 버전을 찾아 선택한 앱만 업데이트합니다. 앱마다 스토어를 열 필요가 없습니다.",
        panelCaption: "새 버전이 있는 앱 보기",
        checkNow: "지금 확인",
        checking: "확인 중",
        lastCheckFormat: "마지막 확인 %@",
        neverChecked: "아직 확인하지 않음",
        upToDate: "모든 앱이 최신입니다",
        coverageNote: "Homebrew로 설치한 앱과 App Store 앱이 대상입니다. 자체 업데이트 기능이 있는 앱은 계속 스스로 업데이트합니다.",
        selectAll: "모두 선택",
        clearSelection: "선택 해제",
        updateSelectedFormat: "%d개 업데이트",
        updateOne: "업데이트",
        openAppStore: "App Store 열기",
        appStoreBadge: "App Store",
        storeHint: "이 업데이트가 설치되는 App Store를 엽니다",
        frequencyLabel: "백그라운드에서 확인",
        frequencyOff: "끄기",
        frequencyDaily: "매일",
        frequencyWeekly: "매주",
        nextCheckFormat: "다음 확인 %@",
        notifyToggle: "업데이트가 있을 때 알림",
        includeStoreToggle: "App Store 앱도 포함",
        includeStoreCaption: "스토어에서 받은 앱의 현재 버전을 Apple에 묻습니다. 모든 확인을 이 Mac에서만 하려면 끄세요.",
        packageMissing: "Homebrew가 설치되지 않아 여기서 앱을 업데이트할 수 없습니다.",
        notificationBodyFormat: "%@개 앱에 새 버전이 있습니다.",
        notificationBodyOne: "한 앱에 새 버전이 있습니다.",
        showInPanel: "패널에 표시"
    )
}
