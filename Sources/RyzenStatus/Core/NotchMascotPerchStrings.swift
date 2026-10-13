// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The companion watching from the menu bar while the floating island is open.
struct NotchMascotPerchStrings {
    let title: String
    let caption: String
}

extension FeatureStrings {
    static func notchMascotPerch(_ language: AppLanguage) -> NotchMascotPerchStrings {
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

extension NotchMascotPerchStrings {
    static let enUS = NotchMascotPerchStrings(
        title: "Watch from the menu bar",
        caption: "When the floating island opens, the companion stays up in the menu bar, follows the pointer with its eyes, walks along a little and hops when you click.")
    static let ptBR = NotchMascotPerchStrings(
        title: "Observar da barra de menus",
        caption: "Quando a ilha flutuante abre, o companheiro fica na barra de menus, segue o ponteiro com os olhos, anda um pouco e dá um pulinho quando você clica.")
    static let tr = NotchMascotPerchStrings(
        title: "Menü çubuğundan izle",
        caption: "Yüzen ada açıldığında arkadaş menü çubuğunda kalır, imleci gözleriyle takip eder, biraz yürür ve tıkladığınızda zıplar.")
    static let ru = NotchMascotPerchStrings(
        title: "Наблюдать из строки меню",
        caption: "Когда плавающий остров открыт, компаньон остаётся в строке меню, следит глазами за указателем, немного ходит и подпрыгивает при щелчке.")
    static let es = NotchMascotPerchStrings(
        title: "Mirar desde la barra",
        caption: "Cuando la isla flotante se abre, el compañero se queda en la barra de menús, sigue el puntero con la mirada, camina un poco y da un saltito cuando haces clic.")
    static let sk = NotchMascotPerchStrings(
        title: "Sledovať z panela ponúk",
        caption: "Keď sa plávajúci ostrov otvorí, spoločník zostane v paneli ponúk, sleduje ukazovateľ očami, trochu sa prejde a pri kliknutí poskočí.")
    static let de = NotchMascotPerchStrings(
        title: "Aus der Menüleiste zusehen",
        caption: "Wenn sich die schwebende Insel öffnet, bleibt der Begleiter in der Menüleiste, folgt dem Zeiger mit den Augen, läuft ein Stück mit und hüpft beim Klicken.")
    static let fr = NotchMascotPerchStrings(
        title: "Regarder depuis la barre des menus",
        caption: "Quand l’île flottante s’ouvre, le compagnon reste dans la barre des menus, suit le pointeur des yeux, marche un peu et sautille quand vous cliquez.")
    static let it = NotchMascotPerchStrings(
        title: "Guarda dalla barra dei menu",
        caption: "Quando l’isola fluttuante si apre, il compagno resta nella barra dei menu, segue il puntatore con lo sguardo, cammina un po’ e fa un saltello quando fai clic.")
    static let ja = NotchMascotPerchStrings(
        title: "メニューバーから見守る",
        caption: "フローティングアイランドを開くと、コンパニオンはメニューバーに残り、ポインタを目で追い、少し歩き、クリックすると跳ねます。")
    static let ko = NotchMascotPerchStrings(
        title: "메뉴 막대에서 지켜보기",
        caption: "떠 있는 아일랜드가 열리면 동반자가 메뉴 막대에 남아 포인터를 눈으로 따라가고, 조금 걷고, 클릭하면 폴짝 뜁니다.")
    static let zhHans = NotchMascotPerchStrings(
        title: "在菜单栏中观看",
        caption: "悬浮岛打开时，伙伴会留在菜单栏中，用眼睛跟随指针，跟着走几步，你点按时还会跳一下。")
    static let zhTW = NotchMascotPerchStrings(
        title: "在選單列中觀看",
        caption: "浮動島打開時，夥伴會留在選單列中，用眼睛跟隨指標，跟著走幾步，你按一下時還會跳一下。")
    static let zhHK = NotchMascotPerchStrings(
        title: "在選單列中觀看",
        caption: "浮動島打開時，夥伴會留在選單列中，用眼睛跟隨指標，跟著走幾步，你按一下時還會跳一下。")
    static let uk = NotchMascotPerchStrings(
        title: "Спостерігати з рядка меню",
        caption: "Коли плаваючий острів відкрито, компаньйон лишається в рядку меню, стежить очима за вказівником, трохи ходить і підстрибує, коли ви клацаєте.")
}
