// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Strings for keeping Spaces in a fixed order. Same contract as the other
/// FeatureStrings structs. Foundation-only for the unit harness.
struct SpacesOrderStrings {
    let name: String
    let caption: String
}

extension FeatureStrings {
    static func spacesOrder(_ language: AppLanguage) -> SpacesOrderStrings {
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

extension SpacesOrderStrings {
    static let enUS = SpacesOrderStrings(
        name: "Keep Spaces in a fixed order",
        caption: "Stops macOS from rearranging Spaces by most recent use, so they stay in the order you set. Your previous setting returns when this is turned off. The Dock may restart once to apply the change."
    )

    static let ptBR = SpacesOrderStrings(
        name: "Manter os Espaços em ordem fixa",
        caption: "Impede que o macOS reorganize os Espaços pelo uso mais recente, para que fiquem na ordem que você definiu. A configuração anterior volta ao desligar esta opção. O Dock pode reiniciar uma vez para aplicar a mudança."
    )

    static let tr = SpacesOrderStrings(
        name: "Space sırasını sabit tut",
        caption: "macOS’un Space’leri son kullanıma göre yeniden sıralamasını engeller, böylece belirlediğiniz sırada kalırlar. Seçenek kapatıldığında önceki ayar geri yüklenir. Değişikliği uygulamak için Dock bir kez yeniden başlayabilir."
    )

    static let ru = SpacesOrderStrings(
        name: "Фиксированный порядок Spaces",
        caption: "Не даёт macOS переставлять Spaces по недавнему использованию, чтобы они оставались в заданном порядке. Прежняя настройка вернётся после выключения функции. Для применения Dock может один раз перезапуститься."
    )

    static let es = SpacesOrderStrings(
        name: "Mantener los Espacios en un orden fijo",
        caption: "Evita que macOS reorganice los Espacios según el uso más reciente, para que sigan en el orden que elegiste. Tu ajuste anterior vuelve al desactivar esta opción. El Dock puede reiniciarse una vez para aplicar el cambio."
    )

    static let sk = SpacesOrderStrings(
        name: "Udržať plochy v pevnom poradí",
        caption: "Zabráni systému macOS meniť poradie plôch podľa posledného použitia, takže zostanú v poradí, ktoré ste nastavili. Po vypnutí sa vráti predchádzajúce nastavenie. Dock sa môže raz reštartovať, aby sa zmena použila."
    )

    static let de = SpacesOrderStrings(
        name: "Spaces in fester Reihenfolge halten",
        caption: "Verhindert, dass macOS die Spaces nach der letzten Nutzung neu anordnet, damit sie in deiner Reihenfolge bleiben. Deine vorherige Einstellung kehrt zurück, wenn du dies ausschaltest. Das Dock startet dafür eventuell einmal neu."
    )

    static let fr = SpacesOrderStrings(
        name: "Garder les Espaces dans un ordre fixe",
        caption: "Empêche macOS de réorganiser les Espaces selon leur utilisation récente, pour qu’ils restent dans l’ordre choisi. Votre réglage précédent revient quand cette option est désactivée. Le Dock peut redémarrer une fois pour appliquer le changement."
    )

    static let it = SpacesOrderStrings(
        name: "Mantieni gli Spazi in ordine fisso",
        caption: "Impedisce a macOS di riordinare gli Spazi in base all’uso più recente, così restano nell’ordine che hai scelto. L’impostazione precedente torna quando disattivi questa opzione. Il Dock potrebbe riavviarsi una volta per applicare la modifica."
    )

    static let ja = SpacesOrderStrings(
        name: "スペースの順序を固定",
        caption: "最近の使用状況に応じてmacOSがスペースを並べ替えないようにし、設定した順序を保ちます。オフにすると以前の設定に戻ります。変更を適用するためにDockが一度再起動することがあります。"
    )

    static let ko = SpacesOrderStrings(
        name: "공간 순서 고정",
        caption: "macOS가 최근 사용 순서에 따라 공간을 재정렬하지 않도록 해 정한 순서를 유지합니다. 끄면 이전 설정으로 돌아갑니다. 변경 사항을 적용하려고 Dock이 한 번 다시 시작될 수 있습니다."
    )

    static let zhHans = SpacesOrderStrings(
        name: "固定空间顺序",
        caption: "阻止 macOS 按最近使用情况重新排列空间，让它们保持你设定的顺序。关闭此选项后会恢复之前的设置。为应用更改，Dock 可能会重新启动一次。"
    )

    static let zhTW = SpacesOrderStrings(
        name: "固定桌面空間順序",
        caption: "避免 macOS 依最近使用情況重新排列桌面空間，讓它們維持你設定的順序。關閉此選項後會恢復先前的設定。為套用變更，Dock 可能會重新啟動一次。"
    )

    static let zhHK = SpacesOrderStrings(
        name: "固定桌面空間順序",
        caption: "避免 macOS 依最近使用情況重新排列桌面空間，讓它們維持你設定的順序。關閉此選項後會恢復先前的設定。為套用變更，Dock 可能會重新啟動一次。"
    )

    static let uk = SpacesOrderStrings(
        name: "Фіксований порядок Spaces",
        caption: "Не дає macOS змінювати порядок Spaces за останнім використанням, тож вони лишаються в заданому вами порядку. Попереднє налаштування повернеться, коли цю опцію вимкнено. Dock може один раз перезапуститися, щоб застосувати зміну."
    )
}
