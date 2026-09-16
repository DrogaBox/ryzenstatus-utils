// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Strings for the Settings "Hardware Validation" page — the surface that
/// closes the pending `[REQUIERE-HW]` probes by giving them somewhere to be
/// recorded. The page is AMD-hardware-facing, so it follows the AMD string
/// conventions: technical identifiers (`PASS`, `-amdpnopchk`, `ITE IT86XXE`,
/// `kextstat`) stay untranslated, and every user-facing sentence is localized.
struct ValidationFeatureStrings {
    let sidebarTitle: String
    let header: String
    let footer: String

    let gatesHeader: String
    let gateKextVersion: String
    let gateKextTelemetry: String
    let gatePrivilege: String
    let gateFanTopology: String
    let gateTachValidity: String
    let gateSuperIOFamily: String
    let verdictPass: String
    let verdictFail: String
    let verdictUnknown: String
    let hintKextVersion: String
    let hintKextTelemetry: String
    let hintPrivilege: String
    let hintFanTopology: String
    let hintTachValidity: String
    let hintSuperIOFamily: String

    let checkButton: String
    let checkHint: String

    let probesHeader: String
    let probesFooter: String
    let statusPending: String
    let statusPass: String
    let statusFail: String
    let probeIdentity: String
    let probeDeadMan: String
    let probePwmFloor: String
    let probeThermalGuard: String
    let probeSmuControls: String
    let probeTelemetry: String
    let probeSurfaces: String

    let samplesHeader: String
    let samplesEmpty: String
    let sampleButton: String
    let clearButton: String

    let reportHeader: String
    let copyButton: String
    /// One %@ — the capture timestamp.
    let capturedFormat: String
}

extension ValidationFeatureStrings {
    static func current(_ language: AppLanguage) -> ValidationFeatureStrings {
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

extension FeatureStrings {
    static func validation(_ language: AppLanguage) -> ValidationFeatureStrings {
        ValidationFeatureStrings.current(language)
    }
}

extension L10n {
    var validation: ValidationFeatureStrings {
        FeatureStrings.validation(language)
    }
}

extension ValidationFeatureStrings {
    static let enUS = ValidationFeatureStrings(
        sidebarTitle: "Hardware Validation",
        header: "Hardware Validation Cycle",
        footer: "Evidence comes from this app, never from the command line: --sensors and --selftest each open and close a kext client, and closing one releases every fan back to BIOS — which silently resets the state a probe is measuring. Run the probes in order, with this app running.",
        gatesHeader: "Preconditions",
        gateKextVersion: "Kext revision",
        gateKextTelemetry: "Kext telemetry",
        gatePrivilege: "Privileged access",
        gateFanTopology: "Fan channels",
        gateTachValidity: "Tachometer trust",
        gateSuperIOFamily: "Super I/O family",
        verdictPass: "PASS",
        verdictFail: "FAIL",
        verdictUnknown: "UNKNOWN",
        hintKextVersion: "Load the kext revision the runbook names, then reboot: two different builds can share one version number, so kextstat alone cannot tell them apart.",
        hintKextTelemetry: "The kext is not answering selector 100. Check that both AMD kexts are injected and enabled in your EFI config.",
        hintPrivilege: "Run the app as root or add -amdpnopchk to boot-args. Without privilege the curve never uploads, and the BIOS idle duty (~15%) looks exactly like the floor a probe is meant to prove.",
        hintFanTopology: "No curve-safe channel found. Leave pump headers on BIOS control: throttling a pump raises CPU temperature under load.",
        hintTachValidity: "A channel reports an untrusted or frozen tachometer. A stalled rotor and a dead sensor cannot be told apart, so that channel's RPM must be treated as unknown.",
        hintSuperIOFamily: "This is not the reference Super I/O. The runbook's expected values are calibrated for ITE IT86XXE — read docs/SUPERIO.md before judging a failure.",
        checkButton: "Run preconditions check",
        checkHint: "Runs the privileged, read-only mailbox probe to resolve the privilege gate. It writes nothing: no fan, no voltage, no limit.",
        probesHeader: "Probe checklist",
        probesFooter: "Statuses and samples persist until you clear them, so a cycle that spans reboots keeps its history. Record a sample while a probe runs; copy the report once it is judged.",
        statusPending: "Pending",
        statusPass: "Pass",
        statusFail: "Fail",
        probeIdentity: "Driver identity (kextstat vs the pinned revision)",
        probeDeadMan: "Dead-man switch (manual fan released on app death)",
        probePwmFloor: "Curve PWM floor (1% idle anchor, fan channel)",
        probeThermalGuard: "Emergency guard (GPU-sourced curve, CPU at or above 85 °C)",
        probeSmuControls: "SMU control family (PBO limits, OC gate, frequency override, cHTC)",
        probeTelemetry: "SMU telemetry (package power, per-core grid, L3, PM table)",
        probeSurfaces: "App surfaces (sensors, overclocking page, dashboard)",
        samplesHeader: "Recorded samples",
        samplesEmpty: "No samples recorded yet.",
        sampleButton: "Record sample",
        clearButton: "Clear samples",
        reportHeader: "Evidence report",
        copyButton: "Copy validation report",
        capturedFormat: "Captured: %@"
    )

    static let es = ValidationFeatureStrings(
        sidebarTitle: "Validación de hardware",
        header: "Ciclo de validación en hardware",
        footer: "La evidencia sale de esta app, nunca de la línea de comandos: --sensors y --selftest abren y cierran un cliente del kext, y al cerrarlo se liberan todos los ventiladores a la BIOS, lo que resetea en silencio el estado que un probe está midiendo. Corré los probes en orden, con esta app abierta.",
        gatesHeader: "Precondiciones",
        gateKextVersion: "Revisión del kext",
        gateKextTelemetry: "Telemetría del kext",
        gatePrivilege: "Acceso privilegiado",
        gateFanTopology: "Canales de ventilador",
        gateTachValidity: "Confianza del tacómetro",
        gateSuperIOFamily: "Familia de Super I/O",
        verdictPass: "PASS",
        verdictFail: "FAIL",
        verdictUnknown: "UNKNOWN",
        hintKextVersion: "Cargá la revisión del kext que nombra el runbook y reiniciá: dos builds distintas pueden compartir un número de versión, así que kextstat por sí solo no las distingue.",
        hintKextTelemetry: "El kext no responde al selector 100. Verificá que los dos kexts AMD estén inyectados y habilitados en tu config de EFI.",
        hintPrivilege: "Ejecutá la app como root o agregá -amdpnopchk a los boot-args. Sin privilegio la curva nunca se sube, y el ralentí de la BIOS (~15 %) es idéntico al piso que el probe quiere demostrar.",
        hintFanTopology: "No hay ningún canal seguro para curvas. Dejá los canales de bomba en control de la BIOS: estrangular una bomba sube la temperatura de la CPU bajo carga.",
        hintTachValidity: "Un canal reporta un tacómetro no confiable o congelado. Un rotor calado y un sensor muerto no se pueden distinguir, así que el RPM de ese canal debe tratarse como desconocido.",
        hintSuperIOFamily: "Éste no es el Super I/O de referencia. Los valores esperados del runbook están calibrados para ITE IT86XXE — leé docs/SUPERIO.md antes de juzgar un fallo.",
        checkButton: "Comprobar precondiciones",
        checkHint: "Corre el probe privilegiado y de solo lectura del buzón SMU para resolver la compuerta de privilegio. No escribe nada: ni ventilador, ni voltaje, ni límite.",
        probesHeader: "Lista de probes",
        probesFooter: "Los estados y las muestras persisten hasta que los borres, así un ciclo que abarca reinicios conserva su historial. Registrá una muestra mientras corre un probe; copiá el informe cuando lo juzgues.",
        statusPending: "Pendiente",
        statusPass: "Pasa",
        statusFail: "Falla",
        probeIdentity: "Identidad del driver (kextstat vs la revisión fijada)",
        probeDeadMan: "Dead-man switch (ventilador en manual liberado al morir la app)",
        probePwmFloor: "Piso de PWM en curva (ancla al 1 % en idle, canal de ventilador)",
        probeThermalGuard: "Guard de emergencia (curva con fuente GPU, CPU a 85 °C o más)",
        probeSmuControls: "Familia de control SMU (límites PBO, compuerta OC, anulación de frecuencia, cHTC)",
        probeTelemetry: "Telemetría SMU (potencia del paquete, grilla por núcleo, L3, tabla PM)",
        probeSurfaces: "Superficies de la app (sensores, página de overclocking, dashboard)",
        samplesHeader: "Muestras registradas",
        samplesEmpty: "Todavía no hay muestras registradas.",
        sampleButton: "Registrar muestra",
        clearButton: "Borrar muestras",
        reportHeader: "Informe de evidencia",
        copyButton: "Copiar informe de validación",
        capturedFormat: "Capturado: %@"
    )

    static let ptBR = ValidationFeatureStrings(
        sidebarTitle: "Validação de hardware",
        header: "Ciclo de validação em hardware",
        footer: "A evidência sai deste app, nunca da linha de comando: --sensors e --selftest abrem e fecham um cliente do kext, e ao fechar liberam todas as ventoinhas para a BIOS — o que reinicia silenciosamente o estado que um probe está medindo. Rode os probes em ordem, com este app aberto.",
        gatesHeader: "Pré-condições",
        gateKextVersion: "Revisão do kext",
        gateKextTelemetry: "Telemetria do kext",
        gatePrivilege: "Acesso privilegiado",
        gateFanTopology: "Canais de ventoinha",
        gateTachValidity: "Confiança do tacômetro",
        gateSuperIOFamily: "Família de Super I/O",
        verdictPass: "PASS",
        verdictFail: "FAIL",
        verdictUnknown: "UNKNOWN",
        hintKextVersion: "Carregue a revisão do kext que o runbook indica e reinicie: duas builds diferentes podem compartilhar o mesmo número de versão, então o kextstat sozinho não as distingue.",
        hintKextTelemetry: "O kext não responde ao seletor 100. Verifique se os dois kexts AMD estão injetados e habilitados no seu config de EFI.",
        hintPrivilege: "Rode o app como root ou adicione -amdpnopchk aos boot-args. Sem privilégio a curva nunca é enviada, e o repouso da BIOS (~15 %) é idêntico ao piso que o probe quer provar.",
        hintFanTopology: "Nenhum canal seguro para curvas. Deixe os canais de bomba no controle da BIOS: estrangular uma bomba eleva a temperatura da CPU sob carga.",
        hintTachValidity: "Um canal reporta tacômetro não confiável ou congelado. Rotor travado e sensor morto não se distinguem, então o RPM desse canal deve ser tratado como desconhecido.",
        hintSuperIOFamily: "Este não é o Super I/O de referência. Os valores esperados do runbook são calibrados para ITE IT86XXE — leia docs/SUPERIO.md antes de julgar uma falha.",
        checkButton: "Verificar pré-condições",
        checkHint: "Roda o probe privilegiado e somente leitura do mailbox SMU para resolver a barreira de privilégio. Não grava nada: nem ventoinha, nem tensão, nem limite.",
        probesHeader: "Lista de probes",
        probesFooter: "Estados e amostras persistem até você limpá-los, então um ciclo que atravessa reinicializações mantém seu histórico. Registre uma amostra enquanto um probe roda; copie o relatório quando julgá-lo.",
        statusPending: "Pendente",
        statusPass: "Passa",
        statusFail: "Falha",
        probeIdentity: "Identidade do driver (kextstat vs a revisão fixada)",
        probeDeadMan: "Dead-man switch (ventoinha manual liberada quando o app morre)",
        probePwmFloor: "Piso de PWM em curva (âncora de 1 % em idle, canal de ventoinha)",
        probeThermalGuard: "Guard de emergência (curva com fonte GPU, CPU em 85 °C ou mais)",
        probeSmuControls: "Família de controle SMU (limites PBO, barreira OC, substituição de frequência, cHTC)",
        probeTelemetry: "Telemetria SMU (potência do pacote, grade por núcleo, L3, tabela PM)",
        probeSurfaces: "Superfícies do app (sensores, página de overclocking, dashboard)",
        samplesHeader: "Amostras registradas",
        samplesEmpty: "Nenhuma amostra registrada ainda.",
        sampleButton: "Registrar amostra",
        clearButton: "Limpar amostras",
        reportHeader: "Relatório de evidência",
        copyButton: "Copiar relatório de validação",
        capturedFormat: "Capturado: %@"
    )

    static let de = ValidationFeatureStrings(
        sidebarTitle: "Hardware-Validierung",
        header: "Hardware-Validierungszyklus",
        footer: "Die Evidenz kommt aus dieser App, nie von der Kommandozeile: --sensors und --selftest öffnen und schließen jeweils einen Kext-Client, und beim Schließen werden alle Lüfter an das BIOS zurückgegeben — was genau den Zustand zurücksetzt, den ein Probe misst. Führen Sie die Probes der Reihe nach aus, mit laufender App.",
        gatesHeader: "Vorbedingungen",
        gateKextVersion: "Kext-Revision",
        gateKextTelemetry: "Kext-Telemetrie",
        gatePrivilege: "Privilegierter Zugriff",
        gateFanTopology: "Lüfterkanäle",
        gateTachValidity: "Vertrauen des Drehzahlsensors",
        gateSuperIOFamily: "Super-I/O-Familie",
        verdictPass: "PASS",
        verdictFail: "FAIL",
        verdictUnknown: "UNKNOWN",
        hintKextVersion: "Laden Sie die im Runbook genannte Kext-Revision und starten Sie neu: zwei verschiedene Builds können dieselbe Versionsnummer tragen, kextstat allein unterscheidet sie nicht.",
        hintKextTelemetry: "Der Kext antwortet nicht auf Selektor 100. Prüfen Sie, ob beide AMD-Kexts in Ihrer EFI-Konfiguration eingebunden und aktiviert sind.",
        hintPrivilege: "Starten Sie die App als root oder setzen Sie -amdpnopchk in die boot-args. Ohne Privileg wird die Kurve nie hochgeladen, und die BIOS-Leerlaufdrehzahl (~15 %) sieht genau wie der Boden aus, den ein Probe beweisen soll.",
        hintFanTopology: "Kein kurvensicherer Kanal gefunden. Lassen Sie Pumpenanschlüsse unter BIOS-Kontrolle: eine gedrosselte Pumpe erhöht die CPU-Temperatur unter Last.",
        hintTachValidity: "Ein Kanal meldet einen unzuverlässigen oder eingefrorenen Drehzahlsensor. Ein blockierter Rotor und ein defekter Sensor sind nicht unterscheidbar, daher gilt die Drehzahl dieses Kanals als unbekannt.",
        hintSuperIOFamily: "Dies ist nicht das Referenz-Super-I/O. Die Erwartungswerte des Runbooks sind auf ITE IT86XXE kalibriert — lesen Sie docs/SUPERIO.md, bevor Sie einen Fehlschlag bewerten.",
        checkButton: "Vorbedingungen prüfen",
        checkHint: "Führt den privilegierten Nur-Lese-Probe der SMU-Mailbox aus, um das Privileg-Gate aufzulösen. Er schreibt nichts: keinen Lüfter, keine Spannung, kein Limit.",
        probesHeader: "Probe-Checkliste",
        probesFooter: "Status und Messwerte bleiben erhalten, bis Sie sie löschen, damit ein Zyklus über Neustarts hinweg seine Historie behält. Zeichnen Sie einen Messwert auf, während ein Probe läuft; kopieren Sie den Bericht, sobald er bewertet ist.",
        statusPending: "Offen",
        statusPass: "Bestanden",
        statusFail: "Fehlgeschlagen",
        probeIdentity: "Treiberidentität (kextstat gegen die fixierte Revision)",
        probeDeadMan: "Dead-Man-Schalter (manueller Lüfter bei App-Absturz freigegeben)",
        probePwmFloor: "Kurven-PWM-Boden (1 % Anker im Leerlauf, Lüfterkanal)",
        probeThermalGuard: "Notfallschutz (GPU-Kurve, CPU bei oder über 85 °C)",
        probeSmuControls: "SMU-Steuerfamilie (PBO-Limits, OC-Gate, Frequenz-Override, cHTC)",
        probeTelemetry: "SMU-Telemetrie (Paketleistung, Kernraster, L3, PM-Tabelle)",
        probeSurfaces: "App-Oberflächen (Sensoren, Overclocking-Seite, Dashboard)",
        samplesHeader: "Aufgezeichnete Messwerte",
        samplesEmpty: "Noch keine Messwerte aufgezeichnet.",
        sampleButton: "Messwert aufzeichnen",
        clearButton: "Messwerte löschen",
        reportHeader: "Evidenzbericht",
        copyButton: "Validierungsbericht kopieren",
        capturedFormat: "Erfasst: %@"
    )

    static let fr = ValidationFeatureStrings(
        sidebarTitle: "Validation matérielle",
        header: "Cycle de validation matérielle",
        footer: "Les preuves viennent de cette app, jamais de la ligne de commande : --sensors et --selftest ouvrent puis ferment chacun un client du kext, et cette fermeture rend tous les ventilateurs au BIOS — ce qui réinitialise en silence l'état qu'une sonde mesure. Lancez les sondes dans l'ordre, l'app ouverte.",
        gatesHeader: "Préconditions",
        gateKextVersion: "Révision du kext",
        gateKextTelemetry: "Télémétrie du kext",
        gatePrivilege: "Accès privilégié",
        gateFanTopology: "Canaux de ventilateur",
        gateTachValidity: "Confiance du compte-tours",
        gateSuperIOFamily: "Famille de Super I/O",
        verdictPass: "PASS",
        verdictFail: "FAIL",
        verdictUnknown: "UNKNOWN",
        hintKextVersion: "Chargez la révision du kext citée par le runbook puis redémarrez : deux builds différents peuvent partager un même numéro de version, kextstat seul ne les distingue pas.",
        hintKextTelemetry: "Le kext ne répond pas au sélecteur 100. Vérifiez que les deux kexts AMD sont injectés et activés dans votre configuration EFI.",
        hintPrivilege: "Lancez l'app en root ou ajoutez -amdpnopchk aux boot-args. Sans privilège la courbe ne s'envoie jamais, et le ralenti du BIOS (~15 %) ressemble exactement au plancher qu'une sonde doit démontrer.",
        hintFanTopology: "Aucun canal sûr pour une courbe. Laissez les canaux de pompe sous contrôle du BIOS : brider une pompe fait monter la température du CPU en charge.",
        hintTachValidity: "Un canal signale un compte-tours non fiable ou figé. Un rotor bloqué et un capteur mort sont indiscernables, le régime de ce canal doit donc être traité comme inconnu.",
        hintSuperIOFamily: "Ce n'est pas le Super I/O de référence. Les valeurs attendues du runbook sont calibrées pour ITE IT86XXE — lisez docs/SUPERIO.md avant de juger un échec.",
        checkButton: "Vérifier les préconditions",
        checkHint: "Exécute la sonde privilégiée en lecture seule de la boîte aux lettres SMU pour trancher la condition de privilège. Elle n'écrit rien : ni ventilateur, ni tension, ni limite.",
        probesHeader: "Liste des sondes",
        probesFooter: "États et échantillons persistent jusqu'à ce que vous les effaciez, afin qu'un cycle couvrant des redémarrages conserve son historique. Enregistrez un échantillon pendant qu'une sonde tourne ; copiez le rapport une fois jugée.",
        statusPending: "En attente",
        statusPass: "Réussi",
        statusFail: "Échec",
        probeIdentity: "Identité du pilote (kextstat contre la révision figée)",
        probeDeadMan: "Interrupteur homme-mort (ventilateur manuel libéré à la mort de l'app)",
        probePwmFloor: "Plancher PWM en courbe (ancre 1 % au repos, canal ventilateur)",
        probeThermalGuard: "Garde d'urgence (courbe source GPU, CPU à 85 °C ou plus)",
        probeSmuControls: "Famille de contrôle SMU (limites PBO, verrou OC, forçage de fréquence, cHTC)",
        probeTelemetry: "Télémétrie SMU (puissance du package, grille par cœur, L3, table PM)",
        probeSurfaces: "Surfaces de l'app (capteurs, page overclocking, tableau de bord)",
        samplesHeader: "Échantillons enregistrés",
        samplesEmpty: "Aucun échantillon enregistré pour l'instant.",
        sampleButton: "Enregistrer un échantillon",
        clearButton: "Effacer les échantillons",
        reportHeader: "Rapport de preuve",
        copyButton: "Copier le rapport de validation",
        capturedFormat: "Capturé : %@"
    )

    static let it = ValidationFeatureStrings(
        sidebarTitle: "Validazione hardware",
        header: "Ciclo di validazione hardware",
        footer: "Le prove vengono da questa app, mai dalla riga di comando: --sensors e --selftest aprono e chiudono ciascuno un client del kext, e alla chiusura tutte le ventole tornano al BIOS — resettando in silenzio lo stato che un probe sta misurando. Esegui i probe in ordine, con l'app aperta.",
        gatesHeader: "Precondizioni",
        gateKextVersion: "Revisione del kext",
        gateKextTelemetry: "Telemetria del kext",
        gatePrivilege: "Accesso privilegiato",
        gateFanTopology: "Canali ventola",
        gateTachValidity: "Affidabilità del tachimetro",
        gateSuperIOFamily: "Famiglia Super I/O",
        verdictPass: "PASS",
        verdictFail: "FAIL",
        verdictUnknown: "UNKNOWN",
        hintKextVersion: "Carica la revisione del kext indicata dal runbook e riavvia: due build diverse possono condividere lo stesso numero di versione, kextstat da solo non le distingue.",
        hintKextTelemetry: "Il kext non risponde al selettore 100. Verifica che entrambi i kext AMD siano iniettati e abilitati nella configurazione EFI.",
        hintPrivilege: "Avvia l'app come root o aggiungi -amdpnopchk ai boot-args. Senza privilegio la curva non viene mai caricata e il minimo del BIOS (~15 %) è identico al limite che il probe deve dimostrare.",
        hintFanTopology: "Nessun canale sicuro per una curva. Lascia i canali della pompa sotto controllo BIOS: strozzare una pompa alza la temperatura della CPU sotto carico.",
        hintTachValidity: "Un canale riporta un tachimetro non affidabile o bloccato. Rotore fermo e sensore morto sono indistinguibili, quindi il regime di quel canale va considerato sconosciuto.",
        hintSuperIOFamily: "Questo non è il Super I/O di riferimento. I valori attesi dal runbook sono calibrati per ITE IT86XXE — leggi docs/SUPERIO.md prima di giudicare un fallimento.",
        checkButton: "Verifica precondizioni",
        checkHint: "Esegue il probe privilegiato in sola lettura della mailbox SMU per risolvere il gate dei privilegi. Non scrive nulla: né ventole, né tensione, né limiti.",
        probesHeader: "Elenco dei probe",
        probesFooter: "Stati e campioni restano finché non li cancelli, così un ciclo che attraversa riavvii conserva la cronologia. Registra un campione mentre un probe è in corso; copia il report quando lo giudichi.",
        statusPending: "In sospeso",
        statusPass: "Superato",
        statusFail: "Fallito",
        probeIdentity: "Identità del driver (kextstat contro la revisione fissata)",
        probeDeadMan: "Interruttore dead-man (ventola manuale rilasciata alla morte dell'app)",
        probePwmFloor: "Limite PWM in curva (ancora all'1 % in idle, canale ventola)",
        probeThermalGuard: "Guardia d'emergenza (curva con sorgente GPU, CPU a 85 °C o più)",
        probeSmuControls: "Famiglia di controllo SMU (limiti PBO, gate OC, override di frequenza, cHTC)",
        probeTelemetry: "Telemetria SMU (potenza del package, griglia per core, L3, tabella PM)",
        probeSurfaces: "Superfici dell'app (sensori, pagina overclocking, dashboard)",
        samplesHeader: "Campioni registrati",
        samplesEmpty: "Nessun campione registrato finora.",
        sampleButton: "Registra campione",
        clearButton: "Cancella campioni",
        reportHeader: "Report delle prove",
        copyButton: "Copia il report di validazione",
        capturedFormat: "Catturato: %@"
    )

    static let ru = ValidationFeatureStrings(
        sidebarTitle: "Проверка оборудования",
        header: "Цикл проверки на оборудовании",
        footer: "Доказательства берутся из этого приложения, а не из командной строки: --sensors и --selftest открывают и закрывают клиент kext, а при закрытии все вентиляторы возвращаются под управление BIOS — это молча сбрасывает состояние, которое измеряет проверка. Выполняйте проверки по порядку, не закрывая приложение.",
        gatesHeader: "Предусловия",
        gateKextVersion: "Ревизия kext",
        gateKextTelemetry: "Телеметрия kext",
        gatePrivilege: "Привилегированный доступ",
        gateFanTopology: "Каналы вентиляторов",
        gateTachValidity: "Достоверность тахометра",
        gateSuperIOFamily: "Семейство Super I/O",
        verdictPass: "PASS",
        verdictFail: "FAIL",
        verdictUnknown: "UNKNOWN",
        hintKextVersion: "Загрузите указанную в runbook ревизию kext и перезагрузитесь: две разные сборки могут иметь один номер версии, и kextstat их не различит.",
        hintKextTelemetry: "Kext не отвечает на селектор 100. Проверьте, что оба AMD kext внедрены и включены в конфигурации EFI.",
        hintPrivilege: "Запустите приложение от root или добавьте -amdpnopchk в boot-args. Без привилегий кривая не загружается, и обороты BIOS в простое (~15 %) неотличимы от порога, который должна доказать проверка.",
        hintFanTopology: "Не найдено ни одного канала, безопасного для кривой. Оставьте каналы помпы под управлением BIOS: ограничение помпы повышает температуру CPU под нагрузкой.",
        hintTachValidity: "Канал сообщает о недостоверном или замершем тахометре. Остановленный ротор и мёртвый датчик неразличимы, поэтому обороты этого канала следует считать неизвестными.",
        hintSuperIOFamily: "Это не эталонный Super I/O. Ожидаемые значения runbook откалиброваны для ITE IT86XXE — прочитайте docs/SUPERIO.md, прежде чем судить о сбое.",
        checkButton: "Проверить предусловия",
        checkHint: "Запускает привилегированную проверку почтового ящика SMU только для чтения, чтобы определить шлюз привилегий. Ничего не записывает: ни вентиляторы, ни напряжение, ни лимиты.",
        probesHeader: "Список проверок",
        probesFooter: "Статусы и образцы сохраняются, пока вы их не очистите, поэтому цикл, растянутый на несколько перезагрузок, сохраняет историю. Записывайте образец во время проверки; копируйте отчёт после оценки.",
        statusPending: "В ожидании",
        statusPass: "Пройдено",
        statusFail: "Сбой",
        probeIdentity: "Идентичность драйвера (kextstat против закреплённой ревизии)",
        probeDeadMan: "Аварийный сброс (ручной вентилятор освобождается при падении приложения)",
        probePwmFloor: "Порог PWM в режиме кривой (якорь 1 % в простое, канал вентилятора)",
        probeThermalGuard: "Аварийная защита (кривая от GPU, CPU 85 °C и выше)",
        probeSmuControls: "Семейство управления SMU (лимиты PBO, шлюз OC, переопределение частоты, cHTC)",
        probeTelemetry: "Телеметрия SMU (мощность пакета, сетка по ядрам, L3, таблица PM)",
        probeSurfaces: "Интерфейсы приложения (датчики, разгон, дашборд)",
        samplesHeader: "Записанные образцы",
        samplesEmpty: "Образцы ещё не записаны.",
        sampleButton: "Записать образец",
        clearButton: "Очистить образцы",
        reportHeader: "Отчёт о доказательствах",
        copyButton: "Скопировать отчёт проверки",
        capturedFormat: "Записано: %@"
    )

    static let tr = ValidationFeatureStrings(
        sidebarTitle: "Donanım Doğrulaması",
        header: "Donanım Doğrulama Döngüsü",
        footer: "Kanıt bu uygulamadan gelir, komut satırından asla: --sensors ve --selftest birer kext istemcisi açıp kapatır ve kapanışta tüm fanlar BIOS'a geri verilir — bu da bir probun ölçtüğü durumu sessizce sıfırlar. Probları sırayla, uygulama açıkken çalıştırın.",
        gatesHeader: "Ön koşullar",
        gateKextVersion: "Kext sürümü",
        gateKextTelemetry: "Kext telemetrisi",
        gatePrivilege: "Ayrıcalıklı erişim",
        gateFanTopology: "Fan kanalları",
        gateTachValidity: "Takometre güvenilirliği",
        gateSuperIOFamily: "Super I/O ailesi",
        verdictPass: "PASS",
        verdictFail: "FAIL",
        verdictUnknown: "UNKNOWN",
        hintKextVersion: "Runbook'ta adı geçen kext sürümünü yükleyip yeniden başlatın: iki farklı derleme aynı sürüm numarasını taşıyabilir, kextstat tek başına onları ayırt edemez.",
        hintKextTelemetry: "Kext, seçici 100'e yanıt vermiyor. İki AMD kextin de EFI yapılandırmanızda eklendiğinden ve etkin olduğundan emin olun.",
        hintPrivilege: "Uygulamayı root olarak çalıştırın ya da boot-args'a -amdpnopchk ekleyin. Ayrıcalık olmadan eğri hiç yüklenmez ve BIOS rölantisi (~%15) tam olarak probun kanıtlaması gereken tabana benzer.",
        hintFanTopology: "Eğri için güvenli kanal bulunamadı. Pompa başlıklarını BIOS denetiminde bırakın: kısılan bir pompa yük altında CPU sıcaklığını yükseltir.",
        hintTachValidity: "Bir kanal güvenilmez veya donmuş takometre bildiriyor. Durmuş rotor ile ölü sensör ayırt edilemez, bu yüzden o kanalın devri bilinmiyor sayılmalıdır.",
        hintSuperIOFamily: "Bu, referans Super I/O değil. Runbook'un beklenen değerleri ITE IT86XXE için kalibre edilmiştir — bir hatayı değerlendirmeden önce docs/SUPERIO.md dosyasını okuyun.",
        checkButton: "Ön koşulları denetle",
        checkHint: "Ayrıcalık kapısını çözmek için SMU posta kutusunun ayrıcalıklı, salt okunur probunu çalıştırır. Hiçbir şey yazmaz: ne fan, ne voltaj, ne limit.",
        probesHeader: "Prob listesi",
        probesFooter: "Durumlar ve örnekler siz temizleyene kadar kalır; böylece yeniden başlatmalara yayılan bir döngü geçmişini korur. Prob çalışırken örnek kaydedin; değerlendirdikten sonra raporu kopyalayın.",
        statusPending: "Bekliyor",
        statusPass: "Geçti",
        statusFail: "Başarısız",
        probeIdentity: "Sürücü kimliği (kextstat ile sabitlenmiş sürüm)",
        probeDeadMan: "Dead-man anahtarı (uygulama ölürse manuel fan serbest bırakılır)",
        probePwmFloor: "Eğri PWM tabanı (boşta %1 çapa, fan kanalı)",
        probeThermalGuard: "Acil durum koruması (GPU kaynaklı eğri, CPU 85 °C veya üzeri)",
        probeSmuControls: "SMU denetim ailesi (PBO limitleri, OC kapısı, frekans geçersiz kılma, cHTC)",
        probeTelemetry: "SMU telemetrisi (paket gücü, çekirdek ızgarası, L3, PM tablosu)",
        probeSurfaces: "Uygulama yüzeyleri (sensörler, overclocking sayfası, gösterge paneli)",
        samplesHeader: "Kaydedilen örnekler",
        samplesEmpty: "Henüz örnek kaydedilmedi.",
        sampleButton: "Örnek kaydet",
        clearButton: "Örnekleri temizle",
        reportHeader: "Kanıt raporu",
        copyButton: "Doğrulama raporunu kopyala",
        capturedFormat: "Kaydedildi: %@"
    )

    static let ja = ValidationFeatureStrings(
        sidebarTitle: "ハードウェア検証",
        header: "ハードウェア検証サイクル",
        footer: "証拠は常にこのアプリから取得します。コマンドラインは使いません。--sensors と --selftest はそれぞれ kext クライアントを開いて閉じ、閉じる際にすべてのファンを BIOS に返すため、プローブが測定している状態が黙って初期化されます。アプリを起動したまま、順番にプローブを実行してください。",
        gatesHeader: "前提条件",
        gateKextVersion: "kext リビジョン",
        gateKextTelemetry: "kext テレメトリ",
        gatePrivilege: "特権アクセス",
        gateFanTopology: "ファンチャンネル",
        gateTachValidity: "タコメーターの信頼性",
        gateSuperIOFamily: "Super I/O ファミリー",
        verdictPass: "PASS",
        verdictFail: "FAIL",
        verdictUnknown: "UNKNOWN",
        hintKextVersion: "ランブックに記載された kext リビジョンを読み込んで再起動してください。別のビルドが同じバージョン番号を持つことがあり、kextstat だけでは区別できません。",
        hintKextTelemetry: "kext がセレクタ 100 に応答していません。EFI 設定で両方の AMD kext が注入され有効になっているか確認してください。",
        hintPrivilege: "アプリを root で実行するか、boot-args に -amdpnopchk を追加してください。特権がないとカーブは決してアップロードされず、BIOS のアイドル duty（約 15%）はプローブが証明すべき下限と見分けがつきません。",
        hintFanTopology: "カーブに安全なチャンネルがありません。ポンプ接続は BIOS 管理のままにしてください。ポンプを絞ると負荷時の CPU 温度が上がります。",
        hintTachValidity: "信頼できない、または固着したタコメーターを報告しているチャンネルがあります。停止したローターと故障したセンサーは区別できないため、そのチャンネルの回転数は不明として扱ってください。",
        hintSuperIOFamily: "これは参照用の Super I/O ではありません。ランブックの期待値は ITE IT86XXE 用に調整されています。失敗を判断する前に docs/SUPERIO.md を読んでください。",
        checkButton: "前提条件を確認",
        checkHint: "特権ゲートを判定するため、SMU メールボックスの特権付き読み取り専用プローブを実行します。ファン、電圧、リミットのいずれも書き込みません。",
        probesHeader: "プローブ チェックリスト",
        probesFooter: "状態とサンプルは消去するまで保持されるため、再起動をまたぐサイクルでも履歴が残ります。プローブ実行中にサンプルを記録し、判定後にレポートをコピーしてください。",
        statusPending: "保留",
        statusPass: "合格",
        statusFail: "不合格",
        probeIdentity: "ドライバー同一性（kextstat と固定リビジョンの照合）",
        probeDeadMan: "デッドマンスイッチ（アプリ終了時に手動ファンを解放）",
        probePwmFloor: "カーブ PWM 下限（アイドル時 1% アンカー、ファンチャンネル）",
        probeThermalGuard: "緊急ガード（GPU 由来のカーブ、CPU 85 °C 以上）",
        probeSmuControls: "SMU 制御ファミリー（PBO リミット、OC ゲート、周波数上書き、cHTC）",
        probeTelemetry: "SMU テレメトリ（パッケージ電力、コアグリッド、L3、PM テーブル）",
        probeSurfaces: "アプリの画面（センサー、オーバークロックページ、ダッシュボード）",
        samplesHeader: "記録したサンプル",
        samplesEmpty: "まだサンプルがありません。",
        sampleButton: "サンプルを記録",
        clearButton: "サンプルを消去",
        reportHeader: "証拠レポート",
        copyButton: "検証レポートをコピー",
        capturedFormat: "取得: %@"
    )

    static let ko = ValidationFeatureStrings(
        sidebarTitle: "하드웨어 검증",
        header: "하드웨어 검증 주기",
        footer: "증거는 항상 이 앱에서 나옵니다. 명령줄은 사용하지 않습니다. --sensors와 --selftest는 각각 kext 클라이언트를 열고 닫으며, 닫을 때 모든 팬을 BIOS로 반환하므로 프로브가 측정하는 상태가 조용히 초기화됩니다. 앱을 켜 둔 채 순서대로 프로브를 실행하세요.",
        gatesHeader: "사전 조건",
        gateKextVersion: "kext 리비전",
        gateKextTelemetry: "kext 텔레메트리",
        gatePrivilege: "권한 있는 접근",
        gateFanTopology: "팬 채널",
        gateTachValidity: "타코미터 신뢰도",
        gateSuperIOFamily: "Super I/O 계열",
        verdictPass: "PASS",
        verdictFail: "FAIL",
        verdictUnknown: "UNKNOWN",
        hintKextVersion: "런북에 적힌 kext 리비전을 올리고 재부팅하세요. 서로 다른 빌드가 같은 버전 번호를 가질 수 있어 kextstat만으로는 구분할 수 없습니다.",
        hintKextTelemetry: "kext가 선택자 100에 응답하지 않습니다. EFI 구성에서 두 AMD kext가 모두 주입되고 활성화되었는지 확인하세요.",
        hintPrivilege: "앱을 root로 실행하거나 boot-args에 -amdpnopchk를 추가하세요. 권한이 없으면 커브가 업로드되지 않고, BIOS 유휴 duty(약 15%)는 프로브가 입증하려는 하한과 구분되지 않습니다.",
        hintFanTopology: "커브에 안전한 채널이 없습니다. 펌프 헤더는 BIOS 제어로 두세요. 펌프를 조이면 부하 시 CPU 온도가 올라갑니다.",
        hintTachValidity: "신뢰할 수 없거나 고정된 타코미터를 보고하는 채널이 있습니다. 멈춘 로터와 고장 난 센서는 구분할 수 없으므로 그 채널의 RPM은 알 수 없는 값으로 취급해야 합니다.",
        hintSuperIOFamily: "이것은 기준 Super I/O가 아닙니다. 런북의 기대값은 ITE IT86XXE에 맞춰 보정되어 있습니다. 실패를 판단하기 전에 docs/SUPERIO.md를 읽으세요.",
        checkButton: "사전 조건 확인",
        checkHint: "권한 게이트를 판정하기 위해 SMU 메일박스의 권한 있는 읽기 전용 프로브를 실행합니다. 팬, 전압, 한계 어느 것도 쓰지 않습니다.",
        probesHeader: "프로브 체크리스트",
        probesFooter: "상태와 샘플은 지울 때까지 유지되어, 재부팅을 거치는 주기도 이력을 보존합니다. 프로브가 도는 동안 샘플을 기록하고, 판정한 뒤 보고서를 복사하세요.",
        statusPending: "대기",
        statusPass: "통과",
        statusFail: "실패",
        probeIdentity: "드라이버 동일성(kextstat 대 고정 리비전)",
        probeDeadMan: "데드맨 스위치(앱 종료 시 수동 팬 해제)",
        probePwmFloor: "커브 PWM 하한(유휴 1% 앵커, 팬 채널)",
        probeThermalGuard: "비상 가드(GPU 소스 커브, CPU 85 °C 이상)",
        probeSmuControls: "SMU 제어 계열(PBO 한계, OC 게이트, 주파수 재정의, cHTC)",
        probeTelemetry: "SMU 텔레메트리(패키지 전력, 코어 그리드, L3, PM 테이블)",
        probeSurfaces: "앱 화면(센서, 오버클러킹 페이지, 대시보드)",
        samplesHeader: "기록된 샘플",
        samplesEmpty: "아직 기록된 샘플이 없습니다.",
        sampleButton: "샘플 기록",
        clearButton: "샘플 지우기",
        reportHeader: "증거 보고서",
        copyButton: "검증 보고서 복사",
        capturedFormat: "기록 시각: %@"
    )

    static let zhHans = ValidationFeatureStrings(
        sidebarTitle: "硬件验证",
        header: "硬件验证周期",
        footer: "证据始终来自此应用，绝不来自命令行：--sensors 与 --selftest 各自会打开并关闭一个 kext 客户端，而关闭时所有风扇都会交还 BIOS，从而静默重置探针正在测量的状态。请在应用运行时按顺序执行探针。",
        gatesHeader: "前置条件",
        gateKextVersion: "kext 版本",
        gateKextTelemetry: "kext 遥测",
        gatePrivilege: "特权访问",
        gateFanTopology: "风扇通道",
        gateTachValidity: "转速计可信度",
        gateSuperIOFamily: "Super I/O 系列",
        verdictPass: "PASS",
        verdictFail: "FAIL",
        verdictUnknown: "UNKNOWN",
        hintKextVersion: "加载运行手册所指的 kext 版本后重启：不同的构建可能共用同一版本号，仅凭 kextstat 无法区分。",
        hintKextTelemetry: "kext 未响应选择器 100。请检查两个 AMD kext 是否都已在 EFI 配置中注入并启用。",
        hintPrivilege: "以 root 运行应用，或在 boot-args 中添加 -amdpnopchk。没有特权时曲线永远不会上传，而 BIOS 空闲占空比（约 15%）与探针要证明的下限完全无法区分。",
        hintFanTopology: "没有可用于曲线的安全通道。请让水泵接口保持 BIOS 控制：限制水泵会在负载下提高 CPU 温度。",
        hintTachValidity: "某个通道报告的转速计不可信或已冻结。停转的转子与失效的传感器无法区分，因此该通道的转速必须视为未知。",
        hintSuperIOFamily: "这不是参考 Super I/O。运行手册的期望值为 ITE IT86XXE 校准——判断失败前请先阅读 docs/SUPERIO.md。",
        checkButton: "检查前置条件",
        checkHint: "运行 SMU 邮箱的特权只读探针以判定特权门槛。它不写入任何内容：不写风扇、不写电压、不写限制。",
        probesHeader: "探针清单",
        probesFooter: "状态与样本会一直保留到你清除为止，因此跨越重启的周期仍保留历史。探针运行期间记录样本，判定后再复制报告。",
        statusPending: "待定",
        statusPass: "通过",
        statusFail: "失败",
        probeIdentity: "驱动身份（kextstat 与固定版本比对）",
        probeDeadMan: "安全开关（应用终止时释放手动风扇）",
        probePwmFloor: "曲线 PWM 下限（空闲 1% 锚点，风扇通道）",
        probeThermalGuard: "紧急保护（GPU 来源曲线，CPU 达 85 °C 或以上）",
        probeSmuControls: "SMU 控制系列（PBO 限制、OC 门槛、频率覆盖、cHTC）",
        probeTelemetry: "SMU 遥测（封装功耗、每核网格、L3、PM 表）",
        probeSurfaces: "应用界面（传感器、超频页面、仪表板）",
        samplesHeader: "已记录样本",
        samplesEmpty: "尚未记录任何样本。",
        sampleButton: "记录样本",
        clearButton: "清除样本",
        reportHeader: "证据报告",
        copyButton: "复制验证报告",
        capturedFormat: "采集于：%@"
    )

    static let zhTW = ValidationFeatureStrings(
        sidebarTitle: "硬體驗證",
        header: "硬體驗證週期",
        footer: "證據一律來自此 App，絕不來自命令列：--sensors 與 --selftest 各自會開啟並關閉一個 kext 用戶端，而關閉時所有風扇都會交還 BIOS，因而靜默重設探針正在量測的狀態。請在 App 執行時依序執行探針。",
        gatesHeader: "前置條件",
        gateKextVersion: "kext 版本",
        gateKextTelemetry: "kext 遙測",
        gatePrivilege: "特權存取",
        gateFanTopology: "風扇通道",
        gateTachValidity: "轉速計可信度",
        gateSuperIOFamily: "Super I/O 系列",
        verdictPass: "PASS",
        verdictFail: "FAIL",
        verdictUnknown: "UNKNOWN",
        hintKextVersion: "載入執行手冊所指的 kext 版本後重新啟動：不同的建置可能共用同一版本號，單憑 kextstat 無法區分。",
        hintKextTelemetry: "kext 未回應選擇器 100。請確認兩個 AMD kext 都已注入並在 EFI 設定中啟用。",
        hintPrivilege: "以 root 執行 App，或在 boot-args 加入 -amdpnopchk。沒有特權時曲線永遠不會上傳，而 BIOS 閒置佔空比（約 15%）與探針要證明的下限完全無法區分。",
        hintFanTopology: "沒有可用於曲線的安全通道。請讓水泵接頭維持 BIOS 控制：限制水泵會在高負載下提高 CPU 溫度。",
        hintTachValidity: "某個通道回報的轉速計不可信或已凍結。停轉的轉子與失效的感測器無法區分，因此該通道的轉速必須視為未知。",
        hintSuperIOFamily: "這不是參考 Super I/O。執行手冊的期望值是以 ITE IT86XXE 校準——判斷失敗前請先閱讀 docs/SUPERIO.md。",
        checkButton: "檢查前置條件",
        checkHint: "執行 SMU 信箱的特權唯讀探針以判定特權門檻。它不寫入任何內容：不寫風扇、不寫電壓、不寫限制。",
        probesHeader: "探針清單",
        probesFooter: "狀態與樣本會保留到你清除為止，因此跨越重新啟動的週期仍保有歷史。探針執行期間記錄樣本，判定後再複製報告。",
        statusPending: "待定",
        statusPass: "通過",
        statusFail: "失敗",
        probeIdentity: "驅動身分（kextstat 與固定版本比對）",
        probeDeadMan: "安全開關（App 終止時釋放手動風扇）",
        probePwmFloor: "曲線 PWM 下限（閒置 1% 錨點，風扇通道）",
        probeThermalGuard: "緊急保護（GPU 來源曲線，CPU 達 85 °C 以上）",
        probeSmuControls: "SMU 控制系列（PBO 限制、OC 門檻、頻率覆寫、cHTC）",
        probeTelemetry: "SMU 遙測（封裝功耗、每核網格、L3、PM 表）",
        probeSurfaces: "App 介面（感測器、超頻頁面、儀表板）",
        samplesHeader: "已記錄樣本",
        samplesEmpty: "尚未記錄任何樣本。",
        sampleButton: "記錄樣本",
        clearButton: "清除樣本",
        reportHeader: "證據報告",
        copyButton: "複製驗證報告",
        capturedFormat: "擷取於：%@"
    )

    static let zhHK = zhTW
}
