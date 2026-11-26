// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Settings > GPU control > Profiles: the saved GPU setups. A profile is a
/// name for what the page holds (a power limit, or a fan curve with zero RPM,
/// the GFX clocks and the voltage), and this section loads one with the
/// checks the controls above make.
struct GPUControlProfileStrings {
    let section: String
    let empty: String
    let footer: String
    let saveCurrent: String
    let saveTitle: String
    let renameTitle: String
    let nameLabel: String
    let saveAction: String
    let cancel: String
    /// %@ = the name already taken.
    let duplicateName: String
    let load: String
    let rename: String
    let delete: String
    let deleteTitle: String
    /// %@ = the profile's name.
    let deleteMessage: String
    let matches: String
    /// %@ = the profile's name.
    let loadedFormat: String
    /// %1$@ = the profile's name, %2$@ = what was left out.
    let leftOutFormat: String
    let raiseNeedsOverclock: String
    let otherCard: String
    let nothingToSave: String
    let listSeparator: String
    let listLastSeparator: String
    let fieldPower: String
    let fieldFanCurve: String
    let fieldZeroRpm: String
    let fieldGfxMax: String
    let fieldGfxMin: String
    let fieldVolt: String
    let fieldRaise: String
    let blockedWriting: String
    let blockedDriver: String
    let blockedOther: String
    let blockedOD8: String
    let blockedFan: String
    let blockedOutOfRange: String

    /// One part of a profile, in words: the sentence about what was left out.
    func field(_ field: GPUControlProfileField) -> String {
        switch field {
        case .power: return fieldPower
        case .fanCurve: return fieldFanCurve
        case .zeroRpm: return fieldZeroRpm
        case .gfxMax: return fieldGfxMax
        case .gfxMin: return fieldGfxMin
        case .volt: return fieldVolt
        case .raise: return fieldRaise
        }
    }

    /// Every text, for the tests.
    var all: [String] {
        [section, empty, footer, saveCurrent, saveTitle, renameTitle, nameLabel, saveAction, cancel,
         duplicateName, load, rename, delete, deleteTitle, deleteMessage, matches, loadedFormat,
         leftOutFormat, raiseNeedsOverclock, otherCard, nothingToSave, listSeparator, listLastSeparator,
         fieldPower, fieldFanCurve, fieldZeroRpm, fieldGfxMax, fieldGfxMin, fieldVolt, fieldRaise,
         blockedWriting, blockedDriver, blockedOther, blockedOD8, blockedFan, blockedOutOfRange]
    }
}

extension FeatureStrings {
    static func gpuControlProfile(_ language: AppLanguage) -> GPUControlProfileStrings {
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

extension GPUControlProfileStrings {
    static let enUS = GPUControlProfileStrings(
        section: "Profiles",
        empty: "No profiles yet.",
        footer: "A profile keeps a power limit, or a fan curve with zero RPM, the GFX clocks and the voltage. Loading one sends it the way the controls above do, so every limit is checked again; with Remember on, the card keeps it like any other change.",
        saveCurrent: "Save current settings…",
        saveTitle: "Save the GPU settings as a profile",
        renameTitle: "Rename the profile",
        nameLabel: "Name",
        saveAction: "Save",
        cancel: "Cancel",
        duplicateName: "There is already a profile called “%@”.",
        load: "Load",
        rename: "Rename",
        delete: "Delete",
        deleteTitle: "Delete this profile?",
        deleteMessage: "“%@” is removed from this Mac. What the GPU holds now does not change.",
        matches: "This is what the GPU holds now",
        loadedFormat: "“%@” is in force.",
        leftOutFormat: "“%1$@” went out without %2$@: this card does not take it now.",
        raiseNeedsOverclock: "A raised clock or power limit needs Allow overclocking on.",
        otherCard: "This profile was made on another card: its values were checked against this one.",
        nothingToSave: "Hold a power limit, or a fan, clock or voltage, to save it as a profile.",
        listSeparator: ", ",
        listLastSeparator: " and ",
        fieldPower: "the power limit",
        fieldFanCurve: "the fan curve",
        fieldZeroRpm: "zero RPM off",
        fieldGfxMax: "the GFX maximum",
        fieldGfxMin: "the GFX minimum",
        fieldVolt: "the voltage",
        fieldRaise: "the overclock flag",
        blockedWriting: "GPU changes are closed: open them, then load the profile.",
        blockedDriver: "The driver has not answered yet: try again in a moment.",
        blockedOther: "Another program holds a change: close it before loading a profile.",
        blockedOD8: "The fan and clock table could not be read after the restart: restart the Mac to load this profile.",
        blockedFan: "This kext build was not checked with fan curves: update the kext, or save the profile without the fan part.",
        blockedOutOfRange: "Nothing in this profile is inside this card’s limits now.")

    static let es = GPUControlProfileStrings(
        section: "Perfiles",
        empty: "Todavía no hay perfiles.",
        footer: "Un perfil guarda un límite de potencia, o una curva de ventilador con cero RPM, los relojes de GFX y el voltaje. Al cargarlo se envía como los controles de arriba, así que cada límite se vuelve a comprobar; con Recordar activado, la tarjeta lo mantiene como cualquier otro cambio.",
        saveCurrent: "Guardar los ajustes actuales…",
        saveTitle: "Guardar los ajustes de la GPU como perfil",
        renameTitle: "Cambiar el nombre del perfil",
        nameLabel: "Nombre",
        saveAction: "Guardar",
        cancel: "Cancelar",
        duplicateName: "Ya hay un perfil llamado «%@».",
        load: "Cargar",
        rename: "Renombrar",
        delete: "Eliminar",
        deleteTitle: "¿Eliminar este perfil?",
        deleteMessage: "«%@» se elimina de este Mac. Lo que la GPU mantiene ahora no cambia.",
        matches: "Esto es lo que la GPU mantiene ahora",
        loadedFormat: "«%@» está en vigor.",
        leftOutFormat: "«%1$@» se envió sin %2$@: esta tarjeta no lo acepta ahora.",
        raiseNeedsOverclock: "Un reloj o un límite de potencia subido necesita Permitir overclock activado.",
        otherCard: "Este perfil se creó en otra tarjeta: sus valores se comprobaron con esta.",
        nothingToSave: "Mantén un límite de potencia, o un ventilador, reloj o voltaje, para guardarlo como perfil.",
        listSeparator: ", ",
        listLastSeparator: " y ",
        fieldPower: "el límite de potencia",
        fieldFanCurve: "la curva del ventilador",
        fieldZeroRpm: "cero RPM desactivado",
        fieldGfxMax: "el máximo de GFX",
        fieldGfxMin: "el mínimo de GFX",
        fieldVolt: "el voltaje",
        fieldRaise: "la marca de overclock",
        blockedWriting: "Los cambios en la GPU están cerrados: ábrelos y luego carga el perfil.",
        blockedDriver: "El driver todavía no responde: inténtalo en un momento.",
        blockedOther: "Otro programa mantiene un cambio: ciérralo antes de cargar un perfil.",
        blockedOD8: "No se pudo leer la tabla de ventilador y relojes tras el reinicio: reinicia el Mac para cargar este perfil.",
        blockedFan: "Esta versión del kext no se comprobó con curvas: actualiza el kext o guarda el perfil sin la parte del ventilador.",
        blockedOutOfRange: "Nada de este perfil está dentro de los límites de esta tarjeta ahora.")

    static let ptBR = GPUControlProfileStrings(
        section: "Perfis",
        empty: "Ainda não há perfis.",
        footer: "Um perfil guarda um limite de potência, ou uma curva de ventoinha com zero RPM, os clocks da GFX e a tensão. Ao carregá-lo ele é enviado como os controles acima, então cada limite é conferido de novo; com Lembrar ativado, a placa o mantém como qualquer outra mudança.",
        saveCurrent: "Salvar ajustes atuais…",
        saveTitle: "Salvar os ajustes da GPU como perfil",
        renameTitle: "Renomear o perfil",
        nameLabel: "Nome",
        saveAction: "Salvar",
        cancel: "Cancelar",
        duplicateName: "Já existe um perfil chamado “%@”.",
        load: "Carregar",
        rename: "Renomear",
        delete: "Apagar",
        deleteTitle: "Apagar este perfil?",
        deleteMessage: "“%@” é removido deste Mac. O que a GPU mantém agora não muda.",
        matches: "É isto que a GPU mantém agora",
        loadedFormat: "“%@” está em vigor.",
        leftOutFormat: "“%1$@” foi enviado sem %2$@: esta placa não aceita isso agora.",
        raiseNeedsOverclock: "Um clock ou limite de potência elevado precisa de Permitir overclock ativado.",
        otherCard: "Este perfil foi criado em outra placa: os valores foram conferidos com esta.",
        nothingToSave: "Mantenha um limite de potência, ou uma ventoinha, clock ou tensão, para salvar como perfil.",
        listSeparator: ", ",
        listLastSeparator: " e ",
        fieldPower: "o limite de potência",
        fieldFanCurve: "a curva da ventoinha",
        fieldZeroRpm: "zero RPM desligado",
        fieldGfxMax: "o máximo da GFX",
        fieldGfxMin: "o mínimo da GFX",
        fieldVolt: "a tensão",
        fieldRaise: "a marca de overclock",
        blockedWriting: "As mudanças na GPU estão fechadas: abra-as e depois carregue o perfil.",
        blockedDriver: "O driver ainda não respondeu: tente em instantes.",
        blockedOther: "Outro programa mantém uma mudança: feche-a antes de carregar um perfil.",
        blockedOD8: "A tabela de ventoinha e clocks não pôde ser lida após o reinício: reinicie o Mac para carregar este perfil.",
        blockedFan: "Esta versão do kext não foi conferida com curvas: atualize o kext ou salve o perfil sem a parte da ventoinha.",
        blockedOutOfRange: "Nada neste perfil está dentro dos limites desta placa agora.")

    static let tr = GPUControlProfileStrings(
        section: "Profiller",
        empty: "Henüz profil yok.",
        footer: "Bir profil bir güç sınırını, ya da sıfır RPM'li fan eğrisini, GFX saat hızlarını ve gerilimi saklar. Yüklerken yukarıdaki denetimler gibi gönderilir, böylece her sınır yeniden denetlenir; Hatırla açıksa kart onu diğer değişiklikler gibi korur.",
        saveCurrent: "Geçerli ayarları kaydet…",
        saveTitle: "GPU ayarlarını profil olarak kaydet",
        renameTitle: "Profilin adını değiştir",
        nameLabel: "Ad",
        saveAction: "Kaydet",
        cancel: "Vazgeç",
        duplicateName: "“%@” adlı bir profil zaten var.",
        load: "Yükle",
        rename: "Yeniden adlandır",
        delete: "Sil",
        deleteTitle: "Bu profil silinsin mi?",
        deleteMessage: "“%@” bu Mac'ten kaldırılır. GPU'nun şu an tuttukları değişmez.",
        matches: "GPU'nun şu an tuttukları bunlar",
        loadedFormat: "“%@” yürürlükte.",
        leftOutFormat: "“%1$@” %2$@ olmadan gönderildi: bu kart artık onu kabul etmiyor.",
        raiseNeedsOverclock: "Yükseltilmiş bir saat hızı veya güç sınırı için Hız aşırtmaya izin ver açık olmalı.",
        otherCard: "Bu profil başka bir kartta oluşturuldu: değerleri bu kartla denetlendi.",
        nothingToSave: "Profil olarak kaydetmek için bir güç sınırı, ya da fan, saat hızı veya gerilim tutun.",
        listSeparator: ", ",
        listLastSeparator: " ve ",
        fieldPower: "güç sınırı",
        fieldFanCurve: "fan eğrisi",
        fieldZeroRpm: "sıfır RPM kapalı",
        fieldGfxMax: "GFX üst sınırı",
        fieldGfxMin: "GFX alt sınırı",
        fieldVolt: "gerilim",
        fieldRaise: "hız aşırtma bayrağı",
        blockedWriting: "GPU değişiklikleri kapalı: önce açın, sonra profili yükleyin.",
        blockedDriver: "Sürücü henüz yanıt vermedi: birazdan tekrar deneyin.",
        blockedOther: "Başka bir program bir değişiklik tutuyor: profil yüklemeden önce onu kapatın.",
        blockedOD8: "Yeniden başlatmadan sonra fan ve saat tablosu okunamadı: bu profili yüklemek için Mac'i yeniden başlatın.",
        blockedFan: "Bu kext sürümü fan eğrileriyle denenmedi: kext'i güncelleyin ya da profili fan bölümü olmadan kaydedin.",
        blockedOutOfRange: "Bu profildeki hiçbir değer artık bu kartın sınırları içinde değil.")

    static let ru = GPUControlProfileStrings(
        section: "Профили",
        empty: "Профилей пока нет.",
        footer: "Профиль хранит лимит мощности либо кривую вентилятора с нулевыми оборотами, частоты GFX и напряжение. При загрузке он отправляется так же, как элементы управления выше, поэтому каждый предел проверяется заново; если включено «Запоминать», карта удерживает его как любое другое изменение.",
        saveCurrent: "Сохранить текущие настройки…",
        saveTitle: "Сохранить настройки GPU как профиль",
        renameTitle: "Переименовать профиль",
        nameLabel: "Имя",
        saveAction: "Сохранить",
        cancel: "Отменить",
        duplicateName: "Профиль с именем «%@» уже есть.",
        load: "Загрузить",
        rename: "Переименовать",
        delete: "Удалить",
        deleteTitle: "Удалить этот профиль?",
        deleteMessage: "«%@» будет удалён с этого Mac. То, что сейчас удерживает GPU, не изменится.",
        matches: "Это то, что GPU удерживает сейчас",
        loadedFormat: "«%@» действует.",
        leftOutFormat: "«%1$@» отправлен без %2$@: эта карта сейчас это не принимает.",
        raiseNeedsOverclock: "Для повышенной частоты или лимита мощности нужно включить «Разрешить разгон».",
        otherCard: "Профиль создан на другой карте: его значения проверены по этой.",
        nothingToSave: "Удерживайте лимит мощности либо вентилятор, частоту или напряжение, чтобы сохранить профиль.",
        listSeparator: ", ",
        listLastSeparator: " и ",
        fieldPower: "лимит мощности",
        fieldFanCurve: "кривая вентилятора",
        fieldZeroRpm: "нулевые обороты выключены",
        fieldGfxMax: "максимум GFX",
        fieldGfxMin: "минимум GFX",
        fieldVolt: "напряжение",
        fieldRaise: "флаг разгона",
        blockedWriting: "Изменения GPU закрыты: откройте их, затем загрузите профиль.",
        blockedDriver: "Драйвер ещё не ответил: попробуйте через минуту.",
        blockedOther: "Другая программа удерживает изменение: закройте его перед загрузкой профиля.",
        blockedOD8: "После перезагрузки не удалось прочитать таблицу вентилятора и частот: перезагрузите Mac, чтобы загрузить этот профиль.",
        blockedFan: "Эта сборка kext не проверялась с кривыми вентилятора: обновите kext или сохраните профиль без вентилятора.",
        blockedOutOfRange: "Ничего из этого профиля сейчас не в пределах этой карты.")

    static let sk = GPUControlProfileStrings(
        section: "Profily",
        empty: "Zatiaľ žiadne profily.",
        footer: "Profil uchováva limit výkonu alebo krivku ventilátora s nulovými otáčkami, takty GFX a napätie. Pri načítaní sa odošle ako ovládacie prvky vyššie, takže každý limit sa znova skontroluje; keď je zapnuté Pamätať, karta ho drží ako každú inú zmenu.",
        saveCurrent: "Uložiť aktuálne nastavenia…",
        saveTitle: "Uložiť nastavenia GPU ako profil",
        renameTitle: "Premenovať profil",
        nameLabel: "Názov",
        saveAction: "Uložiť",
        cancel: "Zrušiť",
        duplicateName: "Profil s názvom „%@“ už existuje.",
        load: "Načítať",
        rename: "Premenovať",
        delete: "Odstrániť",
        deleteTitle: "Odstrániť tento profil?",
        deleteMessage: "„%@“ sa odstráni z tohto Macu. To, čo GPU práve drží, sa nemení.",
        matches: "Toto GPU práve drží",
        loadedFormat: "„%@“ platí.",
        leftOutFormat: "„%1$@“ sa odoslal bez %2$@: táto karta to teraz neprijíma.",
        raiseNeedsOverclock: "Zvýšený takt alebo limit výkonu potrebuje zapnuté Povoliť pretaktovanie.",
        otherCard: "Profil vznikol na inej karte: jeho hodnoty sa skontrolovali s touto.",
        nothingToSave: "Držte limit výkonu alebo ventilátor, takt či napätie, aby sa dal uložiť profil.",
        listSeparator: ", ",
        listLastSeparator: " a ",
        fieldPower: "limit výkonu",
        fieldFanCurve: "krivka ventilátora",
        fieldZeroRpm: "nulové otáčky vypnuté",
        fieldGfxMax: "maximum GFX",
        fieldGfxMin: "minimum GFX",
        fieldVolt: "napätie",
        fieldRaise: "príznak pretaktovania",
        blockedWriting: "Zmeny GPU sú zatvorené: otvorte ich a potom načítajte profil.",
        blockedDriver: "Ovládač ešte neodpovedal: skúste o chvíľu.",
        blockedOther: "Iný program drží zmenu: pred načítaním profilu ju zatvorte.",
        blockedOD8: "Po reštarte sa tabuľka ventilátora a taktov neprečítala: na načítanie profilu reštartujte Mac.",
        blockedFan: "Táto verzia kextu nebola overená s krivkami: aktualizujte kext alebo uložte profil bez ventilátora.",
        blockedOutOfRange: "Nič z tohto profilu teraz nie je v limitoch tejto karty.")

    static let de = GPUControlProfileStrings(
        section: "Profile",
        empty: "Noch keine Profile.",
        footer: "Ein Profil hält ein Leistungslimit oder eine Lüfterkurve mit null U/min, die GFX-Takte und die Spannung. Beim Laden geht es denselben Weg wie die Regler oben, also wird jede Grenze erneut geprüft; mit Merken an behält die Karte es wie jede andere Änderung.",
        saveCurrent: "Aktuelle Einstellungen sichern…",
        saveTitle: "Die GPU-Einstellungen als Profil sichern",
        renameTitle: "Profil umbenennen",
        nameLabel: "Name",
        saveAction: "Sichern",
        cancel: "Abbrechen",
        duplicateName: "Ein Profil namens „%@“ gibt es schon.",
        load: "Laden",
        rename: "Umbenennen",
        delete: "Löschen",
        deleteTitle: "Dieses Profil löschen?",
        deleteMessage: "„%@“ wird von diesem Mac entfernt. Was die GPU gerade hält, bleibt.",
        matches: "Das hält die GPU gerade",
        loadedFormat: "„%@“ ist aktiv.",
        leftOutFormat: "„%1$@“ ging ohne %2$@ raus: diese Karte nimmt das gerade nicht.",
        raiseNeedsOverclock: "Ein erhöhter Takt oder ein höheres Leistungslimit braucht eingeschaltetes Übertakten erlauben.",
        otherCard: "Dieses Profil entstand auf einer anderen Karte: seine Werte wurden an dieser geprüft.",
        nothingToSave: "Halte ein Leistungslimit oder Lüfter, Takt bzw. Spannung, um ein Profil zu sichern.",
        listSeparator: ", ",
        listLastSeparator: " und ",
        fieldPower: "das Leistungslimit",
        fieldFanCurve: "die Lüfterkurve",
        fieldZeroRpm: "Null-U/min aus",
        fieldGfxMax: "der GFX-Höchsttakt",
        fieldGfxMin: "der GFX-Mindesttakt",
        fieldVolt: "die Spannung",
        fieldRaise: "die Übertaktungsmarke",
        blockedWriting: "GPU-Änderungen sind geschlossen: erst öffnen, dann das Profil laden.",
        blockedDriver: "Der Treiber hat noch nicht geantwortet: gleich noch einmal versuchen.",
        blockedOther: "Ein anderes Programm hält eine Änderung: vor dem Laden schließen.",
        blockedOD8: "Lüfter- und Takt-Tabelle war nach dem Neustart nicht lesbar: zum Laden den Mac neu starten.",
        blockedFan: "Diese kext-Version wurde nicht mit Kurven geprüft: Kext aktualisieren oder das Profil ohne Lüfter sichern.",
        blockedOutOfRange: "Nichts aus diesem Profil liegt gerade in den Grenzen dieser Karte.")

    static let fr = GPUControlProfileStrings(
        section: "Profils",
        empty: "Aucun profil pour l’instant.",
        footer: "Un profil garde une limite de puissance, ou une courbe de ventilateur avec zéro tr/min, les fréquences GFX et la tension. Au chargement, il part comme les réglages ci-dessus, donc chaque limite est revérifiée ; avec Mémoriser activé, la carte le garde comme tout autre changement.",
        saveCurrent: "Enregistrer les réglages actuels…",
        saveTitle: "Enregistrer les réglages du GPU comme profil",
        renameTitle: "Renommer le profil",
        nameLabel: "Nom",
        saveAction: "Enregistrer",
        cancel: "Annuler",
        duplicateName: "Un profil nommé « %@ » existe déjà.",
        load: "Charger",
        rename: "Renommer",
        delete: "Supprimer",
        deleteTitle: "Supprimer ce profil ?",
        deleteMessage: "« %@ » est retiré de ce Mac. Ce que le GPU tient maintenant ne change pas.",
        matches: "C’est ce que le GPU tient maintenant",
        loadedFormat: "« %@ » est en vigueur.",
        leftOutFormat: "« %1$@ » est parti sans %2$@ : cette carte ne l’accepte pas maintenant.",
        raiseNeedsOverclock: "Une fréquence ou une limite de puissance relevée demande Autoriser l’overclocking.",
        otherCard: "Ce profil a été créé sur une autre carte : ses valeurs ont été vérifiées sur celle-ci.",
        nothingToSave: "Tenez une limite de puissance, ou un ventilateur, une fréquence ou une tension, pour l’enregistrer en profil.",
        listSeparator: ", ",
        listLastSeparator: " et ",
        fieldPower: "la limite de puissance",
        fieldFanCurve: "la courbe du ventilateur",
        fieldZeroRpm: "zéro tr/min désactivé",
        fieldGfxMax: "la fréquence GFX maximale",
        fieldGfxMin: "la fréquence GFX minimale",
        fieldVolt: "la tension",
        fieldRaise: "l’indicateur d’overclocking",
        blockedWriting: "Les modifications du GPU sont fermées : ouvrez-les, puis chargez le profil.",
        blockedDriver: "Le pilote n’a pas encore répondu : réessayez dans un instant.",
        blockedOther: "Un autre programme tient un changement : fermez-le avant de charger un profil.",
        blockedOD8: "La table ventilateur et fréquences n’a pas pu être lue après le redémarrage : redémarrez le Mac pour charger ce profil.",
        blockedFan: "Cette version du kext n’a pas été vérifiée avec des courbes : mettez le kext à jour ou enregistrez le profil sans le ventilateur.",
        blockedOutOfRange: "Rien dans ce profil n’est dans les limites de cette carte maintenant.")

    static let it = GPUControlProfileStrings(
        section: "Profili",
        empty: "Ancora nessun profilo.",
        footer: "Un profilo tiene un limite di potenza, oppure una curva della ventola con zero giri, i clock GFX e la tensione. Al caricamento viene inviato come i controlli qui sopra, quindi ogni limite è ricontrollato; con Ricorda attivo la scheda lo mantiene come ogni altra modifica.",
        saveCurrent: "Salva le impostazioni attuali…",
        saveTitle: "Salva le impostazioni GPU come profilo",
        renameTitle: "Rinomina il profilo",
        nameLabel: "Nome",
        saveAction: "Salva",
        cancel: "Annulla",
        duplicateName: "Esiste già un profilo chiamato «%@».",
        load: "Carica",
        rename: "Rinomina",
        delete: "Elimina",
        deleteTitle: "Eliminare questo profilo?",
        deleteMessage: "«%@» viene rimosso da questo Mac. Ciò che la GPU tiene ora non cambia.",
        matches: "Questo è ciò che la GPU tiene ora",
        loadedFormat: "«%@» è in vigore.",
        leftOutFormat: "«%1$@» è stato inviato senza %2$@: questa scheda ora non lo accetta.",
        raiseNeedsOverclock: "Un clock o un limite di potenza alzato richiede Consenti l’overclock attivo.",
        otherCard: "Questo profilo è stato creato su un’altra scheda: i suoi valori sono stati controllati su questa.",
        nothingToSave: "Tieni un limite di potenza, oppure ventola, clock o tensione, per salvarlo come profilo.",
        listSeparator: ", ",
        listLastSeparator: " e ",
        fieldPower: "il limite di potenza",
        fieldFanCurve: "la curva della ventola",
        fieldZeroRpm: "zero giri disattivato",
        fieldGfxMax: "il massimo GFX",
        fieldGfxMin: "il minimo GFX",
        fieldVolt: "la tensione",
        fieldRaise: "il flag di overclock",
        blockedWriting: "Le modifiche GPU sono chiuse: aprile, poi carica il profilo.",
        blockedDriver: "Il driver non ha ancora risposto: riprova tra un momento.",
        blockedOther: "Un altro programma tiene una modifica: chiudila prima di caricare un profilo.",
        blockedOD8: "Dopo il riavvio la tabella di ventola e clock non è leggibile: riavvia il Mac per caricare questo profilo.",
        blockedFan: "Questa versione del kext non è stata provata con le curve: aggiorna il kext o salva il profilo senza la ventola.",
        blockedOutOfRange: "Niente in questo profilo rientra ora nei limiti di questa scheda.")

    static let ja = GPUControlProfileStrings(
        section: "プロファイル",
        empty: "プロファイルはまだありません。",
        footer: "プロファイルは、電力制限、またはゼロ回転を含むファンカーブ、GFX クロック、電圧を保存します。読み込むと上のコントロールと同じ経路で送られるため、すべての上限が再確認されます。「覚える」がオンなら、他の変更と同じようにカードが保持します。",
        saveCurrent: "現在の設定を保存…",
        saveTitle: "GPU の設定をプロファイルとして保存",
        renameTitle: "プロファイルの名前を変更",
        nameLabel: "名前",
        saveAction: "保存",
        cancel: "キャンセル",
        duplicateName: "「%@」という名前のプロファイルはすでにあります。",
        load: "読み込む",
        rename: "名前を変更",
        delete: "削除",
        deleteTitle: "このプロファイルを削除しますか？",
        deleteMessage: "「%@」をこの Mac から削除します。GPU が現在保持している内容は変わりません。",
        matches: "GPU が現在保持している内容",
        loadedFormat: "「%@」が適用されています。",
        leftOutFormat: "「%1$@」は %2$@ なしで送信されました。このカードは現在それを受け付けません。",
        raiseNeedsOverclock: "クロックや電力制限を上げるには「オーバークロックを許可」が必要です。",
        otherCard: "このプロファイルは別のカードで作成されました。値はこのカードで確認されました。",
        nothingToSave: "プロファイルとして保存するには、電力制限、またはファン・クロック・電圧を保持してください。",
        listSeparator: "、",
        listLastSeparator: "と",
        fieldPower: "電力制限",
        fieldFanCurve: "ファンカーブ",
        fieldZeroRpm: "ゼロ回転オフ",
        fieldGfxMax: "GFX 最大クロック",
        fieldGfxMin: "GFX 最小クロック",
        fieldVolt: "電圧",
        fieldRaise: "オーバークロックの指定",
        blockedWriting: "GPU の変更が閉じています。開いてからプロファイルを読み込んでください。",
        blockedDriver: "ドライバがまだ応答していません。少し待ってから試してください。",
        blockedOther: "別のプログラムが変更を保持しています。閉じてから読み込んでください。",
        blockedOD8: "再起動後にファンとクロックの表を読めませんでした。このプロファイルを読み込むには Mac を再起動してください。",
        blockedFan: "この kext ではカーブを確認していません。kext を更新するか、ファンを含めずに保存してください。",
        blockedOutOfRange: "このプロファイルのどの値も、現在このカードの上限内にありません。")

    static let ko = GPUControlProfileStrings(
        section: "프로필",
        empty: "아직 프로필이 없습니다.",
        footer: "프로필은 전력 제한, 또는 제로 RPM을 포함한 팬 곡선, GFX 클록, 전압을 저장합니다. 불러오면 위의 컨트롤과 같은 경로로 전송되므로 모든 한도를 다시 확인합니다. 기억이 켜져 있으면 다른 변경과 마찬가지로 카드가 유지합니다.",
        saveCurrent: "현재 설정 저장…",
        saveTitle: "GPU 설정을 프로필로 저장",
        renameTitle: "프로필 이름 변경",
        nameLabel: "이름",
        saveAction: "저장",
        cancel: "취소",
        duplicateName: "‘%@’ 이름의 프로필이 이미 있습니다.",
        load: "불러오기",
        rename: "이름 변경",
        delete: "삭제",
        deleteTitle: "이 프로필을 삭제할까요?",
        deleteMessage: "‘%@’을(를) 이 Mac에서 제거합니다. GPU가 지금 유지하는 값은 바뀌지 않습니다.",
        matches: "GPU가 지금 유지하는 값",
        loadedFormat: "‘%@’이(가) 적용되었습니다.",
        leftOutFormat: "‘%1$@’은(는) %2$@ 없이 전송되었습니다. 이 카드는 지금 그것을 받지 않습니다.",
        raiseNeedsOverclock: "클록이나 전력 제한을 올리려면 오버클럭 허용이 켜져 있어야 합니다.",
        otherCard: "이 프로필은 다른 카드에서 만들어졌습니다. 값은 이 카드로 확인했습니다.",
        nothingToSave: "프로필로 저장하려면 전력 제한, 또는 팬·클록·전압을 유지하세요.",
        listSeparator: ", ",
        listLastSeparator: " 및 ",
        fieldPower: "전력 제한",
        fieldFanCurve: "팬 곡선",
        fieldZeroRpm: "제로 RPM 끔",
        fieldGfxMax: "GFX 최대 클록",
        fieldGfxMin: "GFX 최소 클록",
        fieldVolt: "전압",
        fieldRaise: "오버클럭 표시",
        blockedWriting: "GPU 변경이 닫혀 있습니다. 먼저 열고 프로필을 불러오세요.",
        blockedDriver: "드라이버가 아직 응답하지 않았습니다. 잠시 후 다시 시도하세요.",
        blockedOther: "다른 프로그램이 변경을 유지하고 있습니다. 닫은 뒤 불러오세요.",
        blockedOD8: "재시동 후 팬과 클록 표를 읽지 못했습니다. 이 프로필을 불러오려면 Mac을 재시동하세요.",
        blockedFan: "이 kext에서는 곡선을 확인하지 않았습니다. kext를 업데이트하거나 팬 없이 저장하세요.",
        blockedOutOfRange: "이 프로필의 어떤 값도 지금 이 카드의 한도 안에 없습니다.")

    static let zhHans = GPUControlProfileStrings(
        section: "配置文件",
        empty: "还没有配置文件。",
        footer: "配置文件保存功率限制，或包含零转速的风扇曲线、GFX 时钟和电压。载入时按上方控件相同的路径发送，因此每个上限都会重新检查；开启“记住”后，显卡会像其他更改一样保持它。",
        saveCurrent: "存储当前设置…",
        saveTitle: "将 GPU 设置存为配置文件",
        renameTitle: "重命名配置文件",
        nameLabel: "名称",
        saveAction: "存储",
        cancel: "取消",
        duplicateName: "已存在名为“%@”的配置文件。",
        load: "载入",
        rename: "重命名",
        delete: "删除",
        deleteTitle: "删除此配置文件？",
        deleteMessage: "“%@”将从此 Mac 移除。GPU 当前保持的内容不会改变。",
        matches: "这是 GPU 当前保持的内容",
        loadedFormat: "“%@”已生效。",
        leftOutFormat: "“%1$@”在发送时去掉了 %2$@：这张显卡现在不接受它。",
        raiseNeedsOverclock: "提高时钟或功率限制需要开启“允许超频”。",
        otherCard: "此配置文件是在另一张显卡上创建的：其中的数值已按这张显卡重新检查。",
        nothingToSave: "请先保持一项功率限制，或风扇、时钟、电压，才能存为配置文件。",
        listSeparator: "、",
        listLastSeparator: "和",
        fieldPower: "功率限制",
        fieldFanCurve: "风扇曲线",
        fieldZeroRpm: "关闭零转速",
        fieldGfxMax: "GFX 最大时钟",
        fieldGfxMin: "GFX 最小时钟",
        fieldVolt: "电压",
        fieldRaise: "超频标志",
        blockedWriting: "GPU 更改已关闭：请先打开，再载入配置文件。",
        blockedDriver: "驱动尚未响应：请稍后再试。",
        blockedOther: "另一个程序正保持更改：请先关闭，再载入配置文件。",
        blockedOD8: "重新启动后无法读取风扇和时钟表：要载入此配置文件，请重新启动 Mac。",
        blockedFan: "此 kext 未用曲线验证过：请更新 kext，或去掉风扇部分再存储。",
        blockedOutOfRange: "此配置文件中的任何值现在都不在这张显卡的范围内。")

    static let zhTW = GPUControlProfileStrings(
        section: "設定檔",
        empty: "還沒有設定檔。",
        footer: "設定檔會保存功率限制，或包含零轉速的風扇曲線、GFX 時脈與電壓。載入時以上方控制項相同的路徑送出，因此每個上限都會重新檢查；開啟「記住」後，顯示卡會像其他變更一樣保持它。",
        saveCurrent: "儲存目前設定…",
        saveTitle: "將 GPU 設定存為設定檔",
        renameTitle: "重新命名設定檔",
        nameLabel: "名稱",
        saveAction: "儲存",
        cancel: "取消",
        duplicateName: "已有名為「%@」的設定檔。",
        load: "載入",
        rename: "重新命名",
        delete: "刪除",
        deleteTitle: "刪除此設定檔？",
        deleteMessage: "「%@」將從此 Mac 移除。GPU 目前保持的內容不會改變。",
        matches: "這是 GPU 目前保持的內容",
        loadedFormat: "「%@」已生效。",
        leftOutFormat: "「%1$@」送出時去掉了 %2$@：這張顯示卡現在不接受它。",
        raiseNeedsOverclock: "提高時脈或功率限制需要開啟「允許超頻」。",
        otherCard: "此設定檔是在另一張顯示卡上建立的：其中的數值已依這張顯示卡重新檢查。",
        nothingToSave: "請先保持一項功率限制，或風扇、時脈、電壓，才能存為設定檔。",
        listSeparator: "、",
        listLastSeparator: "和",
        fieldPower: "功率限制",
        fieldFanCurve: "風扇曲線",
        fieldZeroRpm: "關閉零轉速",
        fieldGfxMax: "GFX 最大時脈",
        fieldGfxMin: "GFX 最小時脈",
        fieldVolt: "電壓",
        fieldRaise: "超頻旗標",
        blockedWriting: "GPU 變更已關閉：請先開啟，再載入設定檔。",
        blockedDriver: "驅動程式尚未回應：請稍後再試。",
        blockedOther: "另一個程式正保持變更：請先關閉，再載入設定檔。",
        blockedOD8: "重新啟動後無法讀取風扇與時脈表：要載入此設定檔，請重新啟動 Mac。",
        blockedFan: "此 kext 未以曲線驗證過：請更新 kext，或去掉風扇部分再儲存。",
        blockedOutOfRange: "此設定檔中的任何值現在都不在這張顯示卡的範圍內。")

    static let uk = GPUControlProfileStrings(
        section: "Профілі",
        empty: "Профілів ще немає.",
        footer: "Профіль зберігає ліміт потужності або криву вентилятора з нульовими обертами, частоти GFX і напругу. Під час завантаження він надсилається так само, як елементи керування вище, тож кожну межу перевірено заново; якщо ввімкнено «Пам’ятати», карта тримає його як будь-яку іншу зміну.",
        saveCurrent: "Зберегти поточні налаштування…",
        saveTitle: "Зберегти налаштування GPU як профіль",
        renameTitle: "Перейменувати профіль",
        nameLabel: "Назва",
        saveAction: "Зберегти",
        cancel: "Скасувати",
        duplicateName: "Профіль із назвою «%@» уже є.",
        load: "Завантажити",
        rename: "Перейменувати",
        delete: "Видалити",
        deleteTitle: "Видалити цей профіль?",
        deleteMessage: "«%@» буде видалено з цього Mac. Те, що GPU тримає зараз, не зміниться.",
        matches: "Це те, що GPU тримає зараз",
        loadedFormat: "«%@» діє.",
        leftOutFormat: "«%1$@» надіслано без %2$@: ця карта зараз цього не приймає.",
        raiseNeedsOverclock: "Для підвищеної частоти чи ліміту потужності потрібно ввімкнути «Дозволити розгін».",
        otherCard: "Профіль створено на іншій карті: його значення перевірено на цій.",
        nothingToSave: "Утримуйте ліміт потужності або вентилятор, частоту чи напругу, щоб зберегти профіль.",
        listSeparator: ", ",
        listLastSeparator: " і ",
        fieldPower: "ліміт потужності",
        fieldFanCurve: "крива вентилятора",
        fieldZeroRpm: "нульові оберти вимкнено",
        fieldGfxMax: "максимум GFX",
        fieldGfxMin: "мінімум GFX",
        fieldVolt: "напруга",
        fieldRaise: "прапорець розгону",
        blockedWriting: "Зміни GPU закрито: відкрийте їх, потім завантажте профіль.",
        blockedDriver: "Драйвер ще не відповів: спробуйте за мить.",
        blockedOther: "Інша програма тримає зміну: закрийте її перед завантаженням профілю.",
        blockedOD8: "Після перезавантаження не вдалося прочитати таблицю вентилятора й частот: перезавантажте Mac, щоб завантажити цей профіль.",
        blockedFan: "Цю збірку kext не перевірено з кривими: оновіть kext або збережіть профіль без вентилятора.",
        blockedOutOfRange: "Нічого з цього профілю зараз не в межах цієї карти.")
}
