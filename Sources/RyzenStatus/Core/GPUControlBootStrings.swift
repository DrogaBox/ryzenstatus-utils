// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Settings > GPU control: "Allow changes after restart too"
/// (`GPUControlBootArm`). Its own table, next to `GPUControlPageStrings`.
struct GPUControlBootStrings {
    let toggle: String
    /// Under the switch: what it does, that it asks once, and what turning
    /// it off does and does not do.
    let footer: String
    /// The ready state's warning while the option is on: changes stay
    /// allowed after a restart too.
    let readyWarning: String
    /// The closed state while the option is on (closed by the owner, or the
    /// start-up has not opened it yet).
    let armClosed: String
    /// The administrator dialog when turning it on.
    let promptOn: String
    /// The administrator dialog when turning it off.
    let promptOff: String
    let failed: String
    /// VoiceOver's hint on the switch.
    let hint: String

    var all: [String] { [toggle, footer, readyWarning, armClosed, promptOn, promptOff, failed, hint] }
}

extension FeatureStrings {
    static func gpuControlBoot(_ language: AppLanguage) -> GPUControlBootStrings {
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

extension GPUControlBootStrings {
    static let enUS = GPUControlBootStrings(
        toggle: "Allow changes after restart too",
        footer: "Asks for an administrator password once. Then GPU changes are allowed again at every startup, without a password. Turning it off asks again and does not close the changes allowed now.",
        readyWarning: "GPU changes are allowed until you close them, and again at every startup: any program on this Mac can change the power limit, the fan and the clock.",
        armClosed: "Changes are allowed again at the next startup. An administrator can also allow them now.",
        promptOn: "Allow changes to the GPU power limit, fan and clock now and at every startup of the Mac.",
        promptOff: "Stop allowing GPU changes at startup.",
        failed: "The startup setting was not changed.",
        hint: "Asks for an administrator password.")

    static let es = GPUControlBootStrings(
        toggle: "Permitir cambios también después de reiniciar",
        footer: "Pide la contraseña de un administrador una sola vez. Después, los cambios en la GPU se vuelven a permitir en cada arranque, sin contraseña. Desactivarlo la pide otra vez y no cierra los cambios permitidos ahora.",
        readyWarning: "Cambios en la GPU permitidos hasta que los cierres, y otra vez en cada arranque: cualquier programa de este Mac puede cambiar el límite de potencia, el ventilador y el reloj.",
        armClosed: "Los cambios se vuelven a permitir en el próximo arranque. Un administrador también puede permitirlos ahora.",
        promptOn: "Permitir cambios en el límite de potencia, el ventilador y el reloj de la GPU ahora y en cada arranque del Mac.",
        promptOff: "Dejar de permitir cambios en la GPU al arrancar.",
        failed: "No se cambió el ajuste de arranque.",
        hint: "Pide la contraseña de un administrador.")

    static let ptBR = GPUControlBootStrings(
        toggle: "Permitir alterações também após reiniciar",
        footer: "Pede a senha de um administrador uma única vez. Depois, as alterações na GPU voltam a ser permitidas a cada inicialização, sem senha. Desativar pede a senha de novo e não fecha as alterações permitidas agora.",
        readyWarning: "Alterações na GPU permitidas até você fechá-las, e de novo a cada inicialização: qualquer programa deste Mac pode alterar o limite de energia, a ventoinha e o clock.",
        armClosed: "As alterações voltam a ser permitidas na próxima inicialização. Um administrador também pode permiti-las agora.",
        promptOn: "Permitir alterações no limite de energia, na ventoinha e no clock da GPU agora e a cada inicialização do Mac.",
        promptOff: "Deixar de permitir alterações na GPU na inicialização.",
        failed: "O ajuste de inicialização não foi alterado.",
        hint: "Pede a senha de um administrador.")

    static let tr = GPUControlBootStrings(
        toggle: "Yeniden başlattıktan sonra da değişikliklere izin ver",
        footer: "Yönetici parolasını yalnızca bir kez sorar. Sonra GPU değişikliklerine her açılışta parola olmadan yeniden izin verilir. Kapatmak parolayı yeniden sorar ve şu anda izin verilen değişiklikleri kapatmaz.",
        readyWarning: "GPU değişikliklerine siz kapatana kadar ve her açılışta yeniden izin verildi: bu Mac'teki herhangi bir program güç sınırını, fanı ve saat hızını değiştirebilir.",
        armClosed: "Değişikliklere bir sonraki açılışta yeniden izin verilir. Bir yönetici şimdi de izin verebilir.",
        promptOn: "GPU güç sınırı, fan ve saat hızı değişikliklerine şimdi ve Mac'in her açılışında izin verin.",
        promptOff: "Açılışta GPU değişikliklerine izin vermeyi durdurun.",
        failed: "Açılış ayarı değiştirilmedi.",
        hint: "Yönetici parolasını sorar.")

    static let ru = GPUControlBootStrings(
        toggle: "Разрешать изменения и после перезапуска",
        footer: "Пароль администратора запрашивается один раз. Затем изменения GPU снова разрешаются при каждом запуске, без пароля. Выключение снова запросит пароль и не закроет изменения, разрешённые сейчас.",
        readyWarning: "Изменения GPU разрешены, пока вы их не закроете, и снова при каждом запуске: любая программа на этом Mac может изменить лимит мощности, вентилятор и частоту.",
        armClosed: "Изменения снова будут разрешены при следующем запуске. Администратор может разрешить их и сейчас.",
        promptOn: "Разрешить изменения лимита мощности, вентилятора и частоты GPU сейчас и при каждом запуске Mac.",
        promptOff: "Больше не разрешать изменения GPU при запуске.",
        failed: "Настройка запуска не изменена.",
        hint: "Запрашивает пароль администратора.")

    static let sk = GPUControlBootStrings(
        toggle: "Povoliť zmeny aj po reštarte",
        footer: "Heslo správcu sa pýta iba raz. Potom sa zmeny GPU znova povolia pri každom spustení, bez hesla. Vypnutie sa na heslo spýta znova a nezatvorí zmeny povolené teraz.",
        readyWarning: "Zmeny GPU sú povolené, kým ich nezatvoríte, a znova pri každom spustení: akýkoľvek program na tomto Macu môže zmeniť limit príkonu, ventilátor a takt.",
        armClosed: "Zmeny sa znova povolia pri ďalšom spustení. Správca ich môže povoliť aj teraz.",
        promptOn: "Povoliť zmeny limitu príkonu, ventilátora a taktu GPU teraz a pri každom spustení Macu.",
        promptOff: "Prestať povoľovať zmeny GPU pri spustení.",
        failed: "Nastavenie spustenia sa nezmenilo.",
        hint: "Pýta sa na heslo správcu.")

    static let de = GPUControlBootStrings(
        toggle: "Änderungen auch nach Neustart erlauben",
        footer: "Fragt einmal nach einem Administratorpasswort. Danach sind GPU-Änderungen bei jedem Start wieder erlaubt, ohne Passwort. Ausschalten fragt erneut und schließt die jetzt erlaubten Änderungen nicht.",
        readyWarning: "GPU-Änderungen sind erlaubt, bis Sie sie schließen, und bei jedem Start erneut: Jedes Programm auf diesem Mac kann Leistungslimit, Lüfter und Takt ändern.",
        armClosed: "Änderungen sind beim nächsten Start wieder erlaubt. Ein Administrator kann sie auch jetzt erlauben.",
        promptOn: "Änderungen an Leistungslimit, Lüfter und Takt der GPU jetzt und bei jedem Start des Mac erlauben.",
        promptOff: "GPU-Änderungen beim Start nicht mehr erlauben.",
        failed: "Die Starteinstellung wurde nicht geändert.",
        hint: "Fragt nach einem Administratorpasswort.")

    static let fr = GPUControlBootStrings(
        toggle: "Autoriser les modifications aussi après un redémarrage",
        footer: "Demande une seule fois le mot de passe d’un administrateur. Ensuite, les modifications du GPU sont de nouveau autorisées à chaque démarrage, sans mot de passe. Le désactiver le redemande et ne ferme pas les modifications autorisées maintenant.",
        readyWarning: "Modifications du GPU autorisées jusqu’à ce que vous les fermiez, et de nouveau à chaque démarrage : tout programme de ce Mac peut changer la limite de puissance, le ventilateur et la fréquence.",
        armClosed: "Les modifications seront de nouveau autorisées au prochain démarrage. Un administrateur peut aussi les autoriser maintenant.",
        promptOn: "Autoriser les modifications de la limite de puissance, du ventilateur et de la fréquence du GPU maintenant et à chaque démarrage du Mac.",
        promptOff: "Ne plus autoriser les modifications du GPU au démarrage.",
        failed: "Le réglage de démarrage n’a pas été modifié.",
        hint: "Demande le mot de passe d’un administrateur.")

    static let it = GPUControlBootStrings(
        toggle: "Consenti modifiche anche dopo il riavvio",
        footer: "Chiede la password di un amministratore una sola volta. Poi le modifiche alla GPU sono di nuovo consentite a ogni avvio, senza password. Disattivarlo la chiede di nuovo e non chiude le modifiche consentite ora.",
        readyWarning: "Modifiche alla GPU consentite finché non le chiudi, e di nuovo a ogni avvio: qualsiasi programma di questo Mac può cambiare il limite di potenza, la ventola e il clock.",
        armClosed: "Le modifiche saranno di nuovo consentite al prossimo avvio. Un amministratore può anche consentirle ora.",
        promptOn: "Consenti modifiche al limite di potenza, alla ventola e al clock della GPU ora e a ogni avvio del Mac.",
        promptOff: "Non consentire più le modifiche alla GPU all’avvio.",
        failed: "L’impostazione di avvio non è stata cambiata.",
        hint: "Chiede la password di un amministratore.")

    static let ja = GPUControlBootStrings(
        toggle: "再起動後も変更を許可",
        footer: "管理者パスワードを一度だけ求めます。その後は起動するたびに、パスワードなしで GPU の変更がふたたび許可されます。オフにするとパスワードをもう一度求めますが、いま許可されている変更は閉じません。",
        readyWarning: "変更を閉じるまで、また起動するたびに GPU の変更が許可されます。この Mac のどのプログラムでも電力制限、ファン、クロックを変更できます。",
        armClosed: "次回の起動時に変更がふたたび許可されます。管理者はいま許可することもできます。",
        promptOn: "GPU の電力制限、ファン、クロックの変更を、いまと Mac を起動するたびに許可します。",
        promptOff: "起動時に GPU の変更を許可するのをやめます。",
        failed: "起動時の設定は変更されませんでした。",
        hint: "管理者パスワードを求めます。")

    static let ko = GPUControlBootStrings(
        toggle: "재시동 후에도 변경 허용",
        footer: "관리자 암호를 한 번만 묻습니다. 그 후에는 시동할 때마다 암호 없이 GPU 변경이 다시 허용됩니다. 끄면 암호를 다시 묻고, 지금 허용된 변경은 닫지 않습니다.",
        readyWarning: "변경을 닫을 때까지, 그리고 시동할 때마다 GPU 변경이 허용됩니다. 이 Mac의 어떤 프로그램이든 전력 한도, 팬, 클록을 바꿀 수 있습니다.",
        armClosed: "다음 시동 때 변경이 다시 허용됩니다. 관리자가 지금 허용할 수도 있습니다.",
        promptOn: "GPU 전력 한도, 팬, 클록 변경을 지금과 Mac을 시동할 때마다 허용합니다.",
        promptOff: "시동할 때 GPU 변경을 더 이상 허용하지 않습니다.",
        failed: "시동 설정이 바뀌지 않았습니다.",
        hint: "관리자 암호를 묻습니다.")

    static let zhHans = GPUControlBootStrings(
        toggle: "重新启动后也允许更改",
        footer: "只询问一次管理员密码。之后每次启动时都会再次允许更改 GPU，无需密码。关闭此项会再次询问密码，并且不会关闭现在已允许的更改。",
        readyWarning: "在你关闭更改前，以及每次启动时，都允许更改 GPU：这台 Mac 上的任何程序都可以更改功率上限、风扇和时钟频率。",
        armClosed: "下次启动时会再次允许更改。管理员也可以现在允许。",
        promptOn: "现在以及每次启动 Mac 时，允许更改 GPU 的功率上限、风扇和时钟频率。",
        promptOff: "启动时不再允许更改 GPU。",
        failed: "启动设置未更改。",
        hint: "需要管理员密码。")

    static let zhTW = GPUControlBootStrings(
        toggle: "重新啟動後也允許更改",
        footer: "只詢問一次管理員密碼。之後每次啟動時都會再次允許更改 GPU，無需密碼。關閉此項會再次詢問密碼，並且不會關閉現在已允許的更改。",
        readyWarning: "在你關閉更改前，以及每次啟動時，都允許更改 GPU：這台 Mac 上的任何程式都可以更改功率上限、風扇和時脈。",
        armClosed: "下次啟動時會再次允許更改。管理員也可以現在允許。",
        promptOn: "現在以及每次啟動 Mac 時，允許更改 GPU 的功率上限、風扇和時脈。",
        promptOff: "啟動時不再允許更改 GPU。",
        failed: "啟動設定未更改。",
        hint: "需要管理員密碼。")

    static let uk = GPUControlBootStrings(
        toggle: "Дозволяти зміни й після перезапуску",
        footer: "Пароль адміністратора запитується один раз. Потім зміни GPU знову дозволяються під час кожного запуску, без пароля. Вимкнення знову запитає пароль і не закриє зміни, дозволені зараз.",
        readyWarning: "Зміни GPU дозволено, доки ви їх не закриєте, і знову під час кожного запуску: будь-яка програма на цьому Mac може змінити ліміт потужності, вентилятор і частоту.",
        armClosed: "Зміни знову буде дозволено під час наступного запуску. Адміністратор може дозволити їх і зараз.",
        promptOn: "Дозволити зміни ліміту потужності, вентилятора й частоти GPU зараз і під час кожного запуску Mac.",
        promptOff: "Більше не дозволяти зміни GPU під час запуску.",
        failed: "Налаштування запуску не змінено.",
        hint: "Запитує пароль адміністратора.")
}
