// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The switch that keeps the app from talking to Bluetooth at all.
struct BluetoothUsageStrings {
    let title: String
    let caption: String
}

extension FeatureStrings {
    static func bluetoothUsage(_ language: AppLanguage) -> BluetoothUsageStrings {
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

extension BluetoothUsageStrings {
    static let enUS = BluetoothUsageStrings(
        title: "Use Bluetooth",
        caption: "Accessory notices, Bluetooth device batteries and switching Bluetooth off during sleep need it. Turn it off on a Mac without Bluetooth or whose Bluetooth answers slowly, such as a Hackintosh, so the app never waits on it.")
    static let ptBR = BluetoothUsageStrings(
        title: "Usar Bluetooth",
        caption: "Os avisos de acessórios, as baterias de dispositivos Bluetooth e desligar o Bluetooth durante o repouso precisam dele. Desative-o num Mac sem Bluetooth ou cujo Bluetooth responde devagar, como um Hackintosh, para que o app nunca espere por ele.")
    static let tr = BluetoothUsageStrings(
        title: "Bluetooth'u kullan",
        caption: "Aksesuar bildirimleri, Bluetooth aygıtlarının pilleri ve uykuda Bluetooth'u kapatma buna ihtiyaç duyar. Bluetooth'u olmayan ya da Bluetooth'u yavaş yanıt veren bir Mac'te (örneğin Hackintosh) kapatın; uygulama onu hiç beklemez.")
    static let ru = BluetoothUsageStrings(
        title: "Использовать Bluetooth",
        caption: "Он нужен для уведомлений об аксессуарах, заряда Bluetooth-устройств и отключения Bluetooth во сне. Выключите его на Mac без Bluetooth или с медленным Bluetooth, например на Hackintosh, чтобы приложение никогда его не ждало.")
    static let es = BluetoothUsageStrings(
        title: "Usar Bluetooth",
        caption: "Lo necesitan los avisos de accesorios, la batería de los dispositivos Bluetooth y apagar el Bluetooth al dormir. Desactívalo en un Mac sin Bluetooth o cuyo Bluetooth responde lento, como un Hackintosh, para que la app nunca lo espere.")
    static let sk = BluetoothUsageStrings(
        title: "Používať Bluetooth",
        caption: "Potrebujú ho upozornenia na príslušenstvo, batérie zariadení Bluetooth a vypínanie Bluetooth počas spánku. Vypnite ho na Macu bez Bluetooth alebo s pomaly reagujúcim Bluetooth, napríklad na Hackintoshi, aby naň aplikácia nikdy nečakala.")
    static let de = BluetoothUsageStrings(
        title: "Bluetooth verwenden",
        caption: "Zubehörhinweise, Akkustände von Bluetooth-Geräten und das Ausschalten von Bluetooth im Ruhezustand brauchen es. Schalte es auf einem Mac ohne Bluetooth oder mit langsam antwortendem Bluetooth aus, etwa einem Hackintosh, damit die App nie darauf wartet.")
    static let fr = BluetoothUsageStrings(
        title: "Utiliser le Bluetooth",
        caption: "Les avis d’accessoires, la batterie des appareils Bluetooth et la coupure du Bluetooth pendant la veille en ont besoin. Désactivez-le sur un Mac sans Bluetooth ou dont le Bluetooth répond lentement, comme un Hackintosh, pour que l’app ne l’attende jamais.")
    static let it = BluetoothUsageStrings(
        title: "Usa Bluetooth",
        caption: "Servono gli avvisi degli accessori, la batteria dei dispositivi Bluetooth e lo spegnimento del Bluetooth durante lo stop. Disattivalo su un Mac senza Bluetooth o con un Bluetooth lento a rispondere, come un Hackintosh, così l’app non lo aspetta mai.")
    static let ja = BluetoothUsageStrings(
        title: "Bluetoothを使用",
        caption: "アクセサリの通知、Bluetoothデバイスのバッテリー、スリープ中のBluetoothオフに必要です。Bluetoothがない、または応答が遅いMac（Hackintoshなど）ではオフにすると、アプリがBluetoothを待つことはありません。")
    static let ko = BluetoothUsageStrings(
        title: "Bluetooth 사용",
        caption: "액세서리 알림, Bluetooth 기기 배터리, 잠자기 중 Bluetooth 끄기에 필요합니다. Bluetooth가 없거나 응답이 느린 Mac(예: Hackintosh)에서는 끄면 앱이 Bluetooth를 기다리지 않습니다.")
    static let zhHans = BluetoothUsageStrings(
        title: "使用蓝牙",
        caption: "配件通知、蓝牙设备电量以及睡眠时关闭蓝牙都需要它。在没有蓝牙或蓝牙响应缓慢的 Mac（例如黑苹果）上关闭它，App 就不会再等待蓝牙。")
    static let zhTW = BluetoothUsageStrings(
        title: "使用藍牙",
        caption: "配件通知、藍牙裝置電量以及睡眠時關閉藍牙都需要它。在沒有藍牙或藍牙回應緩慢的 Mac（例如黑蘋果）上關閉它，App 就不會再等待藍牙。")
    static let zhHK = BluetoothUsageStrings(
        title: "使用藍牙",
        caption: "配件通知、藍牙裝置電量以及睡眠時關閉藍牙都需要它。在沒有藍牙或藍牙回應緩慢的 Mac（例如黑蘋果）上關閉它，App 就不會再等候藍牙。")
    static let uk = BluetoothUsageStrings(
        title: "Використовувати Bluetooth",
        caption: "Він потрібен для сповіщень про аксесуари, заряду Bluetooth-пристроїв і вимкнення Bluetooth у режимі сну. Вимкніть його на Mac без Bluetooth або з повільним Bluetooth, як-от Hackintosh, щоб застосунок ніколи на нього не чекав.")
}
