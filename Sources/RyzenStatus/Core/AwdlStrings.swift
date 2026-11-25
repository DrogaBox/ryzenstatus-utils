// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Strings for the AWDL / AirDrop activity line and its notification. Same
/// contract as the other FeatureStrings structs: memberwise init with
/// labeled arguments in declaration order, one static per language, all in
/// this file. The counts are written as "label: number", so no noun has to
/// agree with them.
struct AwdlStrings {
    let rowTitle: String
    let idle: String
    /// One `%d`: the number of peers.
    let peersFormat: String
    /// One `%d`: the Wi-Fi channel.
    let channelFormat: String
    let led: String
    let ledOff: String
    let ledStatus: String
    let ledSteady: String
    let notifyToggle: String
    let notifyHint: String
    let notificationTitle: String
}

extension FeatureStrings {
    static func awdl(_ language: AppLanguage) -> AwdlStrings {
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

extension AwdlStrings {
    static let enUS = AwdlStrings(
        rowTitle: "AWDL / AirDrop",
        idle: "Idle",
        peersFormat: "Peers: %d",
        channelFormat: "Channel %d",
        led: "Status LED",
        ledOff: "Off",
        ledStatus: "Status",
        ledSteady: "Steady",
        notifyToggle: "AWDL / AirDrop becomes active",
        notifyHint: "Notifies when a nearby device starts exchanging data over AWDL (AirDrop, Sidecar, Continuity). Available with Wi-Fi drivers that report AWDL activity.",
        notificationTitle: "AWDL / AirDrop active"
    )

    static let ptBR = AwdlStrings(
        rowTitle: "AWDL / AirDrop",
        idle: "Inativo",
        peersFormat: "Pares: %d",
        channelFormat: "Canal %d",
        led: "LED de status",
        ledOff: "Desligado",
        ledStatus: "Status",
        ledSteady: "Fixo",
        notifyToggle: "AWDL / AirDrop fica ativo",
        notifyHint: "Avisa quando um dispositivo próximo começa a trocar dados por AWDL (AirDrop, Sidecar, Continuidade). Disponível com drivers de Wi-Fi que informam a atividade AWDL.",
        notificationTitle: "AWDL / AirDrop ativo"
    )

    static let tr = AwdlStrings(
        rowTitle: "AWDL / AirDrop",
        idle: "Boşta",
        peersFormat: "Eşler: %d",
        channelFormat: "Kanal %d",
        led: "Durum LED’i",
        ledOff: "Kapalı",
        ledStatus: "Durum",
        ledSteady: "Sabit",
        notifyToggle: "AWDL / AirDrop etkinleştiğinde",
        notifyHint: "Yakındaki bir aygıt AWDL üzerinden veri alışverişine başladığında bildirir (AirDrop, Sidecar, Süreklilik). AWDL etkinliğini bildiren Wi-Fi sürücüleriyle kullanılabilir.",
        notificationTitle: "AWDL / AirDrop etkin"
    )

    static let ru = AwdlStrings(
        rowTitle: "AWDL / AirDrop",
        idle: "Не активен",
        peersFormat: "Узлы: %d",
        channelFormat: "Канал %d",
        led: "Индикатор",
        ledOff: "Выключен",
        ledStatus: "Состояние",
        ledSteady: "Постоянно",
        notifyToggle: "AWDL / AirDrop становится активным",
        notifyHint: "Уведомляет, когда устройство рядом начинает обмен данными по AWDL (AirDrop, Sidecar, Непрерывность). Доступно с драйверами Wi-Fi, которые сообщают об активности AWDL.",
        notificationTitle: "AWDL / AirDrop активен"
    )

    static let es = AwdlStrings(
        rowTitle: "AWDL / AirDrop",
        idle: "Inactivo",
        peersFormat: "Pares: %d",
        channelFormat: "Canal %d",
        led: "LED de estado",
        ledOff: "Apagado",
        ledStatus: "Estado",
        ledSteady: "Fijo",
        notifyToggle: "AWDL / AirDrop se activa",
        notifyHint: "Avisa cuando un dispositivo cercano empieza a intercambiar datos por AWDL (AirDrop, Sidecar, Continuidad). Disponible con drivers de Wi-Fi que informan la actividad AWDL.",
        notificationTitle: "AWDL / AirDrop activo"
    )

    static let sk = AwdlStrings(
        rowTitle: "AWDL / AirDrop",
        idle: "Nečinné",
        peersFormat: "Partneri: %d",
        channelFormat: "Kanál %d",
        led: "Stavová LED",
        ledOff: "Vypnutá",
        ledStatus: "Stav",
        ledSteady: "Trvalo",
        notifyToggle: "AWDL / AirDrop sa aktivuje",
        notifyHint: "Upozorní, keď zariadenie v blízkosti začne vymieňať údaje cez AWDL (AirDrop, Sidecar, Kontinuita). Dostupné s ovládačmi Wi-Fi, ktoré hlásia aktivitu AWDL.",
        notificationTitle: "AWDL / AirDrop je aktívne"
    )

    static let de = AwdlStrings(
        rowTitle: "AWDL / AirDrop",
        idle: "Inaktiv",
        peersFormat: "Partner: %d",
        channelFormat: "Kanal %d",
        led: "Status-LED",
        ledOff: "Aus",
        ledStatus: "Status",
        ledSteady: "Dauerhaft",
        notifyToggle: "AWDL / AirDrop wird aktiv",
        notifyHint: "Meldet, wenn ein Gerät in der Nähe Daten über AWDL austauscht (AirDrop, Sidecar, Integration). Verfügbar mit WLAN-Treibern, die AWDL-Aktivität melden.",
        notificationTitle: "AWDL / AirDrop aktiv"
    )

    static let fr = AwdlStrings(
        rowTitle: "AWDL / AirDrop",
        idle: "Inactif",
        peersFormat: "Pairs : %d",
        channelFormat: "Canal %d",
        led: "LED d’état",
        ledOff: "Éteinte",
        ledStatus: "État",
        ledSteady: "Fixe",
        notifyToggle: "AWDL / AirDrop devient actif",
        notifyHint: "Avertit quand un appareil proche commence à échanger des données par AWDL (AirDrop, Sidecar, Continuité). Disponible avec les pilotes Wi-Fi qui signalent l’activité AWDL.",
        notificationTitle: "AWDL / AirDrop actif"
    )

    static let it = AwdlStrings(
        rowTitle: "AWDL / AirDrop",
        idle: "Inattivo",
        peersFormat: "Peer: %d",
        channelFormat: "Canale %d",
        led: "LED di stato",
        ledOff: "Spento",
        ledStatus: "Stato",
        ledSteady: "Fisso",
        notifyToggle: "AWDL / AirDrop diventa attivo",
        notifyHint: "Avvisa quando un dispositivo vicino inizia a scambiare dati tramite AWDL (AirDrop, Sidecar, Continuity). Disponibile con i driver Wi-Fi che segnalano l’attività AWDL.",
        notificationTitle: "AWDL / AirDrop attivo"
    )

    static let ja = AwdlStrings(
        rowTitle: "AWDL / AirDrop",
        idle: "待機中",
        peersFormat: "ピア: %d",
        channelFormat: "チャンネル %d",
        led: "状態 LED",
        ledOff: "オフ",
        ledStatus: "状態表示",
        ledSteady: "常時点灯",
        notifyToggle: "AWDL / AirDrop がアクティブになったとき",
        notifyHint: "近くのデバイスが AWDL でデータのやり取りを始めたときに通知します（AirDrop、Sidecar、連係機能）。AWDL の動作を報告する Wi-Fi ドライバーで使えます。",
        notificationTitle: "AWDL / AirDrop がアクティブ"
    )

    static let ko = AwdlStrings(
        rowTitle: "AWDL / AirDrop",
        idle: "대기 중",
        peersFormat: "피어: %d",
        channelFormat: "채널 %d",
        led: "상태 LED",
        ledOff: "끔",
        ledStatus: "상태 표시",
        ledSteady: "항상 켬",
        notifyToggle: "AWDL / AirDrop이 활성화될 때",
        notifyHint: "근처 기기가 AWDL로 데이터를 주고받기 시작하면 알립니다(AirDrop, Sidecar, 연속성). AWDL 활동을 알려 주는 Wi-Fi 드라이버에서 사용할 수 있습니다.",
        notificationTitle: "AWDL / AirDrop 활성"
    )

    static let zhHans = AwdlStrings(
        rowTitle: "AWDL / AirDrop",
        idle: "空闲",
        peersFormat: "对等设备：%d",
        channelFormat: "信道 %d",
        led: "状态指示灯",
        ledOff: "关闭",
        ledStatus: "状态",
        ledSteady: "常亮",
        notifyToggle: "AWDL / AirDrop 变为活跃",
        notifyHint: "附近的设备开始通过 AWDL 交换数据时通知（隔空投送、随航、连续互通）。适用于会报告 AWDL 活动的 Wi-Fi 驱动程序。",
        notificationTitle: "AWDL / AirDrop 活跃"
    )

    static let zhTW = AwdlStrings(
        rowTitle: "AWDL / AirDrop",
        idle: "閒置",
        peersFormat: "對等裝置：%d",
        channelFormat: "頻道 %d",
        led: "狀態指示燈",
        ledOff: "關閉",
        ledStatus: "狀態",
        ledSteady: "恆亮",
        notifyToggle: "AWDL / AirDrop 變為使用中",
        notifyHint: "附近的裝置開始透過 AWDL 交換資料時通知（AirDrop、並行、接續互通）。適用於會回報 AWDL 活動的 Wi-Fi 驅動程式。",
        notificationTitle: "AWDL / AirDrop 使用中"
    )

    static let zhHK = AwdlStrings(
        rowTitle: "AWDL / AirDrop",
        idle: "閒置",
        peersFormat: "對等裝置：%d",
        channelFormat: "頻道 %d",
        led: "狀態指示燈",
        ledOff: "關閉",
        ledStatus: "狀態",
        ledSteady: "長亮",
        notifyToggle: "AWDL / AirDrop 變為使用中",
        notifyHint: "附近的裝置開始透過 AWDL 交換資料時通知（AirDrop、並行、接續互通）。適用於會回報 AWDL 活動的 Wi-Fi 驅動程式。",
        notificationTitle: "AWDL / AirDrop 使用中"
    )

    static let uk = AwdlStrings(
        rowTitle: "AWDL / AirDrop",
        idle: "Неактивний",
        peersFormat: "Вузли: %d",
        channelFormat: "Канал %d",
        led: "Індикатор",
        ledOff: "Вимкнений",
        ledStatus: "Стан",
        ledSteady: "Постійно",
        notifyToggle: "AWDL / AirDrop стає активним",
        notifyHint: "Сповіщає, коли пристрій поруч починає обмін даними через AWDL (AirDrop, Sidecar, Неперервність). Доступно з драйверами Wi-Fi, які повідомляють про активність AWDL.",
        notificationTitle: "AWDL / AirDrop активний"
    )
}
