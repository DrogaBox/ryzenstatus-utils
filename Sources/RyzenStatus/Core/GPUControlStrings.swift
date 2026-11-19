// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The "GPU control" group in Settings > Sensors: what the GPU control in
/// GPUSensors.kext reports about itself. Read only.
struct GPUControlStrings {
    let title: String
    let control: String
    let bootProfile: String
    let powerWatch: String
    let bootPowerLimit: String
    let lastLimitSent: String
    let sleepsWakes: String
    /// Header summaries, a word or two.
    let watching: String
    let waiting: String
    let off: String
    let watchingProfileRequests: String
    let watchingPowerLimit: String
    let watchingInPart: String
    let waitingForDriver: String
    let profileMacOSDefault: String
    /// %@ = the profile's name.
    let profileSetFormat: String
    let profileSetAtBoot: String
    let profileWaiting: String
    let refused: String
    let notSet: String
    let profileDriverChooses: String
    let profilePowerSaving: String
    let profileCompute: String
    /// %@ = the watts, then the firmware's result code (already formatted).
    let notTakenFormat: String
    /// %@ = the watts: sent, but the result could not be read.
    let unconfirmedFormat: String
    let footer: String
}

extension FeatureStrings {
    static func gpuControl(_ language: AppLanguage) -> GPUControlStrings {
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
        case .zhTW, .zhHK: return .zhTW
        case .uk: return .uk
        }
    }
}

extension GPUControlStrings {
    static let enUS = GPUControlStrings(
        title: "GPU control",
        control: "Status",
        bootProfile: "Boot power profile",
        powerWatch: "Power limit",
        bootPowerLimit: "Boot power limit",
        lastLimitSent: "Last limit sent",
        sleepsWakes: "Sleeps / wakes",
        watching: "Watching",
        waiting: "Waiting",
        off: "Off",
        watchingProfileRequests: "Watching profile requests",
        watchingPowerLimit: "Watching limit, sleep and wake",
        watchingInPart: "Watching in part",
        waitingForDriver: "Waiting for the driver",
        profileMacOSDefault: "macOS default (compute)",
        profileSetFormat: "Set at boot: %@",
        profileSetAtBoot: "Set at boot",
        profileWaiting: "Requested, waiting for the driver",
        refused: "Refused",
        notSet: "Not set",
        profileDriverChooses: "chosen by the driver",
        profilePowerSaving: "power saving",
        profileCompute: "compute",
        notTakenFormat: "%@, not taken (code %@)",
        unconfirmedFormat: "%@, not confirmed",
        footer: "Read only. GPUSensors.kext watches the card’s driver; nothing on this page changes the GPU.")

    static let ptBR = GPUControlStrings(
        title: "Controle da GPU",
        control: "Estado",
        bootProfile: "Perfil de energia na inicialização",
        powerWatch: "Limite de energia",
        bootPowerLimit: "Limite de energia na inicialização",
        lastLimitSent: "Último limite enviado",
        sleepsWakes: "Repousos / despertares",
        watching: "Monitorando",
        waiting: "Aguardando",
        off: "Desligado",
        watchingProfileRequests: "Monitorando pedidos de perfil",
        watchingPowerLimit: "Monitorando limite, repouso e despertar",
        watchingInPart: "Monitorando em parte",
        waitingForDriver: "Aguardando o driver",
        profileMacOSDefault: "Padrão do macOS (computação)",
        profileSetFormat: "Definido na inicialização: %@",
        profileSetAtBoot: "Definido na inicialização",
        profileWaiting: "Pedido, aguardando o driver",
        refused: "Recusado",
        notSet: "Não definido",
        profileDriverChooses: "escolhido pelo driver",
        profilePowerSaving: "economia de energia",
        profileCompute: "computação",
        notTakenFormat: "%@, não aceito (código %@)",
        unconfirmedFormat: "%@, não confirmado",
        footer: "Somente leitura. O GPUSensors.kext monitora o driver da placa; nada nesta página altera a GPU.")

    static let tr = GPUControlStrings(
        title: "GPU denetimi",
        control: "Durum",
        bootProfile: "Açılış güç profili",
        powerWatch: "Güç sınırı",
        bootPowerLimit: "Açılıştaki güç sınırı",
        lastLimitSent: "Son gönderilen sınır",
        sleepsWakes: "Uyku / uyanma",
        watching: "İzleniyor",
        waiting: "Bekleniyor",
        off: "Kapalı",
        watchingProfileRequests: "Profil istekleri izleniyor",
        watchingPowerLimit: "Sınır, uyku ve uyanma izleniyor",
        watchingInPart: "Kısmen izleniyor",
        waitingForDriver: "Sürücü bekleniyor",
        profileMacOSDefault: "macOS varsayılanı (hesaplama)",
        profileSetFormat: "Açılışta ayarlandı: %@",
        profileSetAtBoot: "Açılışta ayarlandı",
        profileWaiting: "İstendi, sürücü bekleniyor",
        refused: "Reddedildi",
        notSet: "Ayarlanmadı",
        profileDriverChooses: "sürücü seçer",
        profilePowerSaving: "güç tasarrufu",
        profileCompute: "hesaplama",
        notTakenFormat: "%@, kabul edilmedi (kod %@)",
        unconfirmedFormat: "%@, doğrulanmadı",
        footer: "Yalnızca okuma. GPUSensors.kext kartın sürücüsünü izler; bu sayfadaki hiçbir şey GPU’yu değiştirmez.")

    static let ru = GPUControlStrings(
        title: "Управление ГП",
        control: "Состояние",
        bootProfile: "Профиль питания при загрузке",
        powerWatch: "Лимит мощности",
        bootPowerLimit: "Лимит мощности при загрузке",
        lastLimitSent: "Последний отправленный лимит",
        sleepsWakes: "Сон / пробуждение",
        watching: "Наблюдает",
        waiting: "Ожидание",
        off: "Выключено",
        watchingProfileRequests: "Следит за запросами профиля",
        watchingPowerLimit: "Следит за лимитом, сном и пробуждением",
        watchingInPart: "Следит частично",
        waitingForDriver: "Ожидание драйвера",
        profileMacOSDefault: "По умолчанию macOS (вычисления)",
        profileSetFormat: "Задан при загрузке: %@",
        profileSetAtBoot: "Задан при загрузке",
        profileWaiting: "Запрошен, ожидание драйвера",
        refused: "Отклонено",
        notSet: "Не задан",
        profileDriverChooses: "выбирает драйвер",
        profilePowerSaving: "энергосбережение",
        profileCompute: "вычисления",
        notTakenFormat: "%@, не принят (код %@)",
        unconfirmedFormat: "%@, не подтверждён",
        footer: "Только чтение. GPUSensors.kext следит за драйвером карты; ничто на этой странице не меняет ГП.")

    static let es = GPUControlStrings(
        title: "Control de la GPU",
        control: "Estado",
        bootProfile: "Perfil de energía al arrancar",
        powerWatch: "Límite de potencia",
        bootPowerLimit: "Límite de potencia al arrancar",
        lastLimitSent: "Último límite enviado",
        sleepsWakes: "Reposos / reactivaciones",
        watching: "Vigilando",
        waiting: "Esperando",
        off: "Apagado",
        watchingProfileRequests: "Vigila los pedidos de perfil",
        watchingPowerLimit: "Vigila el límite, el reposo y la reactivación",
        watchingInPart: "Vigila en parte",
        waitingForDriver: "Esperando al controlador",
        profileMacOSDefault: "El de macOS (cómputo)",
        profileSetFormat: "Puesto al arrancar: %@",
        profileSetAtBoot: "Puesto al arrancar",
        profileWaiting: "Pedido, esperando al controlador",
        refused: "Rechazado",
        notSet: "No aplicado",
        profileDriverChooses: "lo elige el controlador",
        profilePowerSaving: "ahorro de energía",
        profileCompute: "cómputo",
        notTakenFormat: "%@, no aceptado (código %@)",
        unconfirmedFormat: "%@, sin confirmar",
        footer: "Solo lectura. GPUSensors.kext vigila el controlador de la tarjeta; nada de esta página cambia la GPU.")

    static let de = GPUControlStrings(
        title: "GPU-Steuerung",
        control: "Status",
        bootProfile: "Energieprofil beim Start",
        powerWatch: "Leistungslimit",
        bootPowerLimit: "Leistungslimit beim Start",
        lastLimitSent: "Zuletzt gesendetes Limit",
        sleepsWakes: "Ruhezustände / Aufwachen",
        watching: "Überwacht",
        waiting: "Wartet",
        off: "Aus",
        watchingProfileRequests: "Überwacht Profilanfragen",
        watchingPowerLimit: "Überwacht Limit, Ruhezustand und Aufwachen",
        watchingInPart: "Überwacht teilweise",
        waitingForDriver: "Wartet auf den Treiber",
        profileMacOSDefault: "macOS-Standard (Berechnung)",
        profileSetFormat: "Beim Start gesetzt: %@",
        profileSetAtBoot: "Beim Start gesetzt",
        profileWaiting: "Angefordert, wartet auf den Treiber",
        refused: "Abgelehnt",
        notSet: "Nicht gesetzt",
        profileDriverChooses: "vom Treiber gewählt",
        profilePowerSaving: "Energiesparen",
        profileCompute: "Berechnung",
        notTakenFormat: "%@, nicht übernommen (Code %@)",
        unconfirmedFormat: "%@, nicht bestätigt",
        footer: "Nur Anzeige. GPUSensors.kext überwacht den Treiber der Karte; nichts auf dieser Seite ändert die GPU.")

    static let fr = GPUControlStrings(
        title: "Contrôle du GPU",
        control: "État",
        bootProfile: "Profil d’alimentation au démarrage",
        powerWatch: "Limite de puissance",
        bootPowerLimit: "Limite de puissance au démarrage",
        lastLimitSent: "Dernière limite envoyée",
        sleepsWakes: "Veilles / réveils",
        watching: "Surveillance",
        waiting: "En attente",
        off: "Désactivé",
        watchingProfileRequests: "Surveille les demandes de profil",
        watchingPowerLimit: "Surveille la limite, la veille et le réveil",
        watchingInPart: "Surveille en partie",
        waitingForDriver: "En attente du pilote",
        profileMacOSDefault: "Valeur de macOS (calcul)",
        profileSetFormat: "Défini au démarrage : %@",
        profileSetAtBoot: "Défini au démarrage",
        profileWaiting: "Demandé, en attente du pilote",
        refused: "Refusé",
        notSet: "Non défini",
        profileDriverChooses: "choisi par le pilote",
        profilePowerSaving: "économie d’énergie",
        profileCompute: "calcul",
        notTakenFormat: "%@, non acceptée (code %@)",
        unconfirmedFormat: "%@, non confirmée",
        footer: "Lecture seule. GPUSensors.kext surveille le pilote de la carte ; rien sur cette page ne modifie le GPU.")

    static let it = GPUControlStrings(
        title: "Controllo GPU",
        control: "Stato",
        bootProfile: "Profilo energetico all’avvio",
        powerWatch: "Limite di potenza",
        bootPowerLimit: "Limite di potenza all’avvio",
        lastLimitSent: "Ultimo limite inviato",
        sleepsWakes: "Stop / risvegli",
        watching: "In osservazione",
        waiting: "In attesa",
        off: "Disattivato",
        watchingProfileRequests: "Osserva le richieste di profilo",
        watchingPowerLimit: "Osserva limite, stop e risveglio",
        watchingInPart: "Osserva in parte",
        waitingForDriver: "In attesa del driver",
        profileMacOSDefault: "Predefinito di macOS (calcolo)",
        profileSetFormat: "Impostato all’avvio: %@",
        profileSetAtBoot: "Impostato all’avvio",
        profileWaiting: "Richiesto, in attesa del driver",
        refused: "Rifiutato",
        notSet: "Non impostato",
        profileDriverChooses: "scelto dal driver",
        profilePowerSaving: "risparmio energetico",
        profileCompute: "calcolo",
        notTakenFormat: "%@, non accettato (codice %@)",
        unconfirmedFormat: "%@, non confermato",
        footer: "Sola lettura. GPUSensors.kext osserva il driver della scheda; nulla in questa pagina modifica la GPU.")

    static let ja = GPUControlStrings(
        title: "GPU 制御",
        control: "状態",
        bootProfile: "起動時の電力プロファイル",
        powerWatch: "電力制限",
        bootPowerLimit: "起動時の電力制限",
        lastLimitSent: "最後に送られた制限",
        sleepsWakes: "スリープ / スリープ解除",
        watching: "監視中",
        waiting: "待機中",
        off: "オフ",
        watchingProfileRequests: "プロファイル要求を監視中",
        watchingPowerLimit: "制限・スリープ・スリープ解除を監視中",
        watchingInPart: "一部を監視中",
        waitingForDriver: "ドライバを待機中",
        profileMacOSDefault: "macOS の既定値（コンピュート）",
        profileSetFormat: "起動時に設定: %@",
        profileSetAtBoot: "起動時に設定",
        profileWaiting: "要求済み、ドライバを待機中",
        refused: "拒否",
        notSet: "未設定",
        profileDriverChooses: "ドライバが選択",
        profilePowerSaving: "省電力",
        profileCompute: "コンピュート",
        notTakenFormat: "%@、未適用（コード %@）",
        unconfirmedFormat: "%@、未確認",
        footer: "読み取り専用。GPUSensors.kext がカードのドライバを監視します。このページで GPU が変わることはありません。")

    static let ko = GPUControlStrings(
        title: "GPU 제어",
        control: "상태",
        bootProfile: "부팅 시 전원 프로필",
        powerWatch: "전력 한도",
        bootPowerLimit: "부팅 시 전력 한도",
        lastLimitSent: "마지막으로 보낸 한도",
        sleepsWakes: "잠자기 / 깨우기",
        watching: "감시 중",
        waiting: "대기 중",
        off: "끔",
        watchingProfileRequests: "프로필 요청 감시 중",
        watchingPowerLimit: "한도, 잠자기, 깨우기 감시 중",
        watchingInPart: "일부 감시 중",
        waitingForDriver: "드라이버 대기 중",
        profileMacOSDefault: "macOS 기본값(컴퓨트)",
        profileSetFormat: "부팅 시 설정됨: %@",
        profileSetAtBoot: "부팅 시 설정됨",
        profileWaiting: "요청됨, 드라이버 대기 중",
        refused: "거부됨",
        notSet: "설정 안 됨",
        profileDriverChooses: "드라이버가 선택",
        profilePowerSaving: "절전",
        profileCompute: "컴퓨트",
        notTakenFormat: "%@, 적용 안 됨(코드 %@)",
        unconfirmedFormat: "%@, 확인 안 됨",
        footer: "읽기 전용. GPUSensors.kext가 카드 드라이버를 감시하며, 이 페이지의 어떤 것도 GPU를 바꾸지 않습니다.")

    static let zhHans = GPUControlStrings(
        title: "GPU 控制",
        control: "状态",
        bootProfile: "启动时的电源配置",
        powerWatch: "功率上限",
        bootPowerLimit: "启动时的功率上限",
        lastLimitSent: "最后发送的上限",
        sleepsWakes: "睡眠 / 唤醒",
        watching: "监视中",
        waiting: "等待中",
        off: "关闭",
        watchingProfileRequests: "监视配置请求",
        watchingPowerLimit: "监视上限、睡眠和唤醒",
        watchingInPart: "部分监视",
        waitingForDriver: "等待驱动程序",
        profileMacOSDefault: "macOS 默认（计算）",
        profileSetFormat: "启动时已设置：%@",
        profileSetAtBoot: "启动时已设置",
        profileWaiting: "已请求，等待驱动程序",
        refused: "已拒绝",
        notSet: "未设置",
        profileDriverChooses: "由驱动程序选择",
        profilePowerSaving: "节能",
        profileCompute: "计算",
        notTakenFormat: "%@，未被接受（代码 %@）",
        unconfirmedFormat: "%@，未确认",
        footer: "只读。GPUSensors.kext 监视显卡的驱动程序；此页面上的任何内容都不会更改 GPU。")

    static let zhTW = GPUControlStrings(
        title: "GPU 控制",
        control: "狀態",
        bootProfile: "開機時的電源設定檔",
        powerWatch: "功率上限",
        bootPowerLimit: "開機時的功率上限",
        lastLimitSent: "最後送出的上限",
        sleepsWakes: "睡眠 / 喚醒",
        watching: "監看中",
        waiting: "等待中",
        off: "關閉",
        watchingProfileRequests: "監看設定檔請求",
        watchingPowerLimit: "監看上限、睡眠與喚醒",
        watchingInPart: "部分監看",
        waitingForDriver: "等待驅動程式",
        profileMacOSDefault: "macOS 預設（運算）",
        profileSetFormat: "開機時已設定：%@",
        profileSetAtBoot: "開機時已設定",
        profileWaiting: "已請求，等待驅動程式",
        refused: "已拒絕",
        notSet: "未設定",
        profileDriverChooses: "由驅動程式選擇",
        profilePowerSaving: "省電",
        profileCompute: "運算",
        notTakenFormat: "%@，未被接受（代碼 %@）",
        unconfirmedFormat: "%@，未確認",
        footer: "唯讀。GPUSensors.kext 監看顯示卡的驅動程式；此頁面上的任何內容都不會變更 GPU。")

    static let sk = GPUControlStrings(
        title: "Ovládanie GPU",
        control: "Stav",
        bootProfile: "Profil napájania pri štarte",
        powerWatch: "Limit príkonu",
        bootPowerLimit: "Limit príkonu pri štarte",
        lastLimitSent: "Posledný odoslaný limit",
        sleepsWakes: "Spánky / prebudenia",
        watching: "Sleduje",
        waiting: "Čaká",
        off: "Vypnuté",
        watchingProfileRequests: "Sleduje požiadavky na profil",
        watchingPowerLimit: "Sleduje limit, spánok a prebudenie",
        watchingInPart: "Sleduje čiastočne",
        waitingForDriver: "Čaká na ovládač",
        profileMacOSDefault: "Predvolený v macOS (výpočty)",
        profileSetFormat: "Nastavený pri štarte: %@",
        profileSetAtBoot: "Nastavený pri štarte",
        profileWaiting: "Vyžiadaný, čaká na ovládač",
        refused: "Odmietnuté",
        notSet: "Nenastavený",
        profileDriverChooses: "vyberá ovládač",
        profilePowerSaving: "úspora energie",
        profileCompute: "výpočty",
        notTakenFormat: "%@, neprijatý (kód %@)",
        unconfirmedFormat: "%@, nepotvrdený",
        footer: "Len na čítanie. GPUSensors.kext sleduje ovládač karty; nič na tejto stránke GPU nemení.")

    static let uk = GPUControlStrings(
        title: "Керування ГП",
        control: "Стан",
        bootProfile: "Профіль живлення під час запуску",
        powerWatch: "Ліміт потужності",
        bootPowerLimit: "Ліміт потужності під час запуску",
        lastLimitSent: "Останній надісланий ліміт",
        sleepsWakes: "Сон / пробудження",
        watching: "Стежить",
        waiting: "Очікування",
        off: "Вимкнено",
        watchingProfileRequests: "Стежить за запитами профілю",
        watchingPowerLimit: "Стежить за лімітом, сном і пробудженням",
        watchingInPart: "Стежить частково",
        waitingForDriver: "Очікування драйвера",
        profileMacOSDefault: "Типовий для macOS (обчислення)",
        profileSetFormat: "Задано під час запуску: %@",
        profileSetAtBoot: "Задано під час запуску",
        profileWaiting: "Запитано, очікування драйвера",
        refused: "Відхилено",
        notSet: "Не задано",
        profileDriverChooses: "обирає драйвер",
        profilePowerSaving: "енергозбереження",
        profileCompute: "обчислення",
        notTakenFormat: "%@, не прийнято (код %@)",
        unconfirmedFormat: "%@, не підтверджено",
        footer: "Лише читання. GPUSensors.kext стежить за драйвером карти; ніщо на цій сторінці не змінює ГП.")
}
