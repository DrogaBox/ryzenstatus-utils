// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

struct AMDPowerFeatureStrings {
    let title: String
    let modeDetectedCPPC: String
    let modeDetectedPStates: String
    let autoEPPActive: String
    let energyProfileManual: String
    let autoEPPThresholds: String
    let idleThresholdLabel: String
    let loadThresholdLabel: String
    let idleThresholdHelp: String
    let loadThresholdHelp: String
    let advancedControls: String
    let autoEPPFooter: String
    let legacyPStatesFooter: String
    let advancedEnergyHeader: String
    let advancedEnergyFooter: String
    let amdPowerControlUnsupported: String
    let energyProfileHeader: String
    let perfMax: String
    let perfBalPlus: String
    let perfBalMinus: String
    let perfEco: String

    let cpuProfileHeader: String
    let cpuProfileFooter: String
    let amdGPUHeader: String
    let amdGPUFooter: String

    let powerPresetsHeader: String
    let powerPresetsFooter: String
    let presetsDisableAutoEppHint: String
    let presetEcoSummary: String
    let presetBalanceSummary: String
    let presetPerformanceSummary: String
    let presetExtremeSummary: String

    let gamingModeTitle: String
    let gamingModeHideIcon: String
    let gamingModeActivePreset: String
    let gamingModeActiveKeepAwake: String
    let gamingModeIconHiddenHint: String
    let gamingModeC6Hint: String
    let gamingModeFooter: String

    let deepCStatesTitle: String
    let c6ActiveBadge: String
    let c6DisabledBadge: String
    let c6Guidance: String

    let cppcTitle: String
    let cppcActiveBadge: String
    let cppcInactiveBadge: String
    let cppcGuidance: String

    let pnopchkTitle: String
    let pnopchkActiveBadge: String
    let pnopchkInactiveBadge: String
    let pnopchkGuidance: String

    let copyAmdArgsButton: String
    let copyAmdArgsGuidance: String
    let copiedToastText: String
}

extension L10n {
    var amdPower: AMDPowerFeatureStrings {
        AMDPowerFeatureStrings.current(language)
    }
}

extension FeatureStrings {
    static func amdPower(_ language: AppLanguage) -> AMDPowerFeatureStrings {
        AMDPowerFeatureStrings.current(language)
    }
}

extension AMDPowerFeatureStrings {
    static func current(_ language: AppLanguage) -> AMDPowerFeatureStrings {
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
        }
    }

    static let enUS = AMDPowerFeatureStrings(
        title: "AMD Ryzen Power Control",
        modeDetectedCPPC: "Mode Detected: CPPC (Auto-EPP)",
        modeDetectedPStates: "Mode Detected: Legacy P-States",
        autoEPPActive: "Auto EPP Active",
        energyProfileManual: "Energy Profile (Manual)",
        autoEPPThresholds: "Auto EPP Thresholds",
        idleThresholdLabel: "Idle Threshold",
        loadThresholdLabel: "Load Threshold",
        idleThresholdHelp: "Below this load % -> Power Save (maximum efficiency)",
        loadThresholdHelp: "Above this load % -> Performance (maximum speed)",
        advancedControls: "Advanced Controls",
        autoEPPFooter: "Auto EPP monitors CPU load and switches between Power Save (idle) and Performance (high load) based on configured thresholds.",
        legacyPStatesFooter: "Modifies global frequency multiplier and voltage by locking the P-State.",
        advancedEnergyHeader: "Advanced Power Controls",
        advancedEnergyFooter: "Disabling CPB or enabling LPM will reduce temperatures and power consumption at the expense of peak performance.",
        amdPowerControlUnsupported: "AMD Power Control is not supported on your processor or kext version.",
        energyProfileHeader: "Energy Profile",
        perfMax: "Performance",
        perfBalPlus: "Balanced Perf",
        perfBalMinus: "Balanced Power",
        perfEco: "Power Save",

        cpuProfileHeader: "CPU Profile",
        cpuProfileFooter: "Architecture and power-management capabilities detected by the kext.",
        amdGPUHeader: "AMD GPU",
        amdGPUFooter: "Dedicated AMD GPU telemetry from the kext (selectors 27-30). Hidden when no AMD discrete GPU is detected.",

        powerPresetsHeader: "Power Presets",
        powerPresetsFooter: "One-tap profiles that apply EPP, CPB and PPM/LPM together. Deep C-States (C6) follow your NVRAM boot-args and require a reboot, so presets don't change them.",
        presetsDisableAutoEppHint: "Applying a preset turns Auto EPP off so the profile sticks.",
        presetEcoSummary: "Power Save EPP · CPB off · LPM on",
        presetBalanceSummary: "Balanced EPP · CPB on",
        presetPerformanceSummary: "Performance EPP · CPB on",
        presetExtremeSummary: "Max EPP · CPB on · no limits",

        gamingModeTitle: "Gaming Mode",
        gamingModeHideIcon: "Hide menu bar icon",
        gamingModeActivePreset: "Extreme preset applied (EPP 0, CPB on)",
        gamingModeActiveKeepAwake: "Keep Awake active (indefinite)",
        gamingModeIconHiddenHint: "Menu bar icon hidden — relaunch RyzenStatus to open Settings",
        gamingModeC6Hint: "C6 still enabled at the NVRAM level — set amdcstate=0 and reboot for the full effect",
        gamingModeFooter: "One click: applies the Extreme power preset, starts Keep Awake indefinitely and hides the menu bar icon. Toggle off, or relaunch the app, to restore your previous profile.",

        deepCStatesTitle: "Deep C-States (C6+)",
        c6ActiveBadge: "amdcstate=0 (NVRAM Active)",
        c6DisabledBadge: "amdcstate=1 (Disabled - Recommended)",
        c6Guidance: "Disabled by default. Recommended OFF on desktop PCs to eliminate core wake latency and audio micro-pops.",

        cppcTitle: "CPPC Active Mode (-amdcppcactive)",
        cppcActiveBadge: "Active (-amdcppcactive)",
        cppcInactiveBadge: "Inactive",
        cppcGuidance: "Allows macOS to manage EPP energy profiles (Performance, Power Save) on AMD Zen processors.",

        pnopchkTitle: "Root Privilege Bypass (-amdpnopchk)",
        pnopchkActiveBadge: "Active (-amdpnopchk)",
        pnopchkInactiveBadge: "Inactive",
        pnopchkGuidance: "Allows adjusting fans, EPP, and P-States without requiring administrator password on every change.",

        copyAmdArgsButton: "Copy AMD Boot-Args",
        copyAmdArgsGuidance: "If OpenCore resets NVRAM on boot, click to copy only our app's AMD boot-args string to paste into your config.plist.",
        copiedToastText: "Copied to clipboard:"
    )

    static let es = AMDPowerFeatureStrings(
        title: "Control de Energía AMD Ryzen",
        modeDetectedCPPC: "Modo Detectado: CPPC (Auto-EPP)",
        modeDetectedPStates: "Modo Detectado: P-States Legacy",
        autoEPPActive: "Auto EPP Activo",
        energyProfileManual: "Perfil de Energía (Manual)",
        autoEPPThresholds: "Umbrales Auto EPP",
        idleThresholdLabel: "Umbral de Inactividad",
        loadThresholdLabel: "Umbral de Carga",
        idleThresholdHelp: "Por debajo de este % de carga -> Power Save (máxima eficiencia)",
        loadThresholdHelp: "Por encima de este % de carga -> Rendimiento (máxima velocidad)",
        advancedControls: "Controles Avanzados",
        autoEPPFooter: "Auto EPP monitorea la carga de la CPU y alterna entre Power Save (inactividad) y Rendimiento (carga alta) según los umbrales configurados.",
        legacyPStatesFooter: "Modifica el multiplicador y voltaje global bloqueando el P-State.",
        advancedEnergyHeader: "Controles Avanzados de Energía",
        advancedEnergyFooter: "Desactivar CPB o activar LPM reducirá las temperaturas y el consumo a costa del rendimiento máximo.",
        amdPowerControlUnsupported: "AMD Power Control no es compatible con tu procesador o versión de kext.",
        energyProfileHeader: "Perfil de Energía",
        perfMax: "Rendimiento",
        perfBalPlus: "Rendimiento Bal.",
        perfBalMinus: "Ahorro Bal.",
        perfEco: "Ahorro Máx.",

        cpuProfileHeader: "Perfil de CPU",
        cpuProfileFooter: "Arquitectura y capacidades de gestión de energía detectadas por el kext.",
        amdGPUHeader: "GPU AMD",
        amdGPUFooter: "Telemetría de GPU AMD dedicada desde el kext (selectores 27-30). Oculta cuando no se detecta una GPU AMD discreta.",

        powerPresetsHeader: "Presets de Energía",
        powerPresetsFooter: "Perfiles de un toque que aplican EPP, CPB y PPM/LPM juntos. Los C-States profundos (C6) siguen tus boot-args de NVRAM y requieren reinicio, por lo que los presets no los modifican.",
        presetsDisableAutoEppHint: "Aplicar un preset desactiva Auto EPP para que el perfil se mantenga.",
        presetEcoSummary: "EPP Ahorro · CPB off · LPM on",
        presetBalanceSummary: "EPP Balanceado · CPB on",
        presetPerformanceSummary: "EPP Rendimiento · CPB on",
        presetExtremeSummary: "EPP Máximo · CPB on · sin límites",

        gamingModeTitle: "Modo Gaming",
        gamingModeHideIcon: "Ocultar ícono de la barra de menús",
        gamingModeActivePreset: "Preset Extreme aplicado (EPP 0, CPB on)",
        gamingModeActiveKeepAwake: "Keep Awake activo (indefinido)",
        gamingModeIconHiddenHint: "Ícono de la barra de menús oculto — relanzá RyzenStatus para abrir Ajustes",
        gamingModeC6Hint: "C6 aún activado a nivel NVRAM — configurá amdcstate=0 y reiniciá para el efecto completo",
        gamingModeFooter: "Un clic: aplica el preset Extreme de energía, inicia Keep Awake indefinidamente y oculta el ícono de la barra de menús. Desactivá el modo, o relanzá la app, para restaurar tu perfil anterior.",

        deepCStatesTitle: "Deep C-States (C6+)",
        c6ActiveBadge: "amdcstate=0 (NVRAM Activo)",
        c6DisabledBadge: "amdcstate=1 (Desactivado - Recomendado)",
        c6Guidance: "Desactivado por defecto. En PC de escritorio se recomienda mantenerlo OFF para evitar latencia de despertado y micro-pops de audio.",

        cppcTitle: "CPPC Active Mode (-amdcppcactive)",
        cppcActiveBadge: "Activo (-amdcppcactive)",
        cppcInactiveBadge: "Inactivo",
        cppcGuidance: "Permite a macOS gestionar perfiles EPP (Rendimiento, Ahorro) en procesadores AMD Zen.",

        pnopchkTitle: "Bypass Privilegios Root (-amdpnopchk)",
        pnopchkActiveBadge: "Activo (-amdpnopchk)",
        pnopchkInactiveBadge: "Inactivo",
        pnopchkGuidance: "Permite ajustar ventiladores, EPP y P-States sin pedir clave sudo en cada cambio.",

        copyAmdArgsButton: "Copiar argumentos AMD",
        copyAmdArgsGuidance: "Si tu OpenCore resetea la NVRAM al reiniciar, usá este botón para copiar únicamente la cadena de argumentos AMD de la app y pegarla en tu config.plist.",
        copiedToastText: "Copiado al portapapeles:"
    )

    static let ptBR = AMDPowerFeatureStrings(
        title: "Controle de Energia AMD Ryzen",
        modeDetectedCPPC: "Modo Detectado: CPPC (Auto-EPP)",
        modeDetectedPStates: "Modo Detectado: P-States Legados",
        autoEPPActive: "Auto EPP Ativo",
        energyProfileManual: "Perfil de Energia (Manual)",
        autoEPPThresholds: "Limiares do Auto EPP",
        idleThresholdLabel: "Limiar de Inatividade",
        loadThresholdLabel: "Limiar de Carga",
        idleThresholdHelp: "Abaixo desta carga % -> Economia de Energia (máxima eficiência)",
        loadThresholdHelp: "Acima desta carga % -> Desempenho (máxima velocidade)",
        advancedControls: "Controles Avançados",
        autoEPPFooter: "O Auto EPP monitora a carga da CPU e alterna entre Economia e Desempenho.",
        legacyPStatesFooter: "Modifica o multiplicador e a voltagem bloqueando o P-State.",
        advancedEnergyHeader: "Controles Avançados de Energia",
        advancedEnergyFooter: "Desativar CPB ou ativar LPM reduzirá temperaturas e consumo.",
        amdPowerControlUnsupported: "O controle de energia AMD não é suportado no seu processador ou kext.",
        energyProfileHeader: "Perfil de Energia",
        perfMax: "Desempenho",
        perfBalPlus: "Desemp. Equil.",
        perfBalMinus: "Econ. Equil.",
        perfEco: "Economia",

        cpuProfileHeader: "Perfil da CPU",
        cpuProfileFooter: "Arquitetura e recursos de energia detectados pela kext.",
        amdGPUHeader: "GPU AMD",
        amdGPUFooter: "Telemetria de GPU dedicada AMD da kext.",

        powerPresetsHeader: "Predefinições de Energia",
        powerPresetsFooter: "Perfis rápidos que aplicam EPP, CPB e PPM/LPM juntos.",
        presetsDisableAutoEppHint: "Aplicar uma predefinição desativa o Auto EPP.",
        presetEcoSummary: "EPP Econômico · CPB off · LPM on",
        presetBalanceSummary: "EPP Equilibrado · CPB on",
        presetPerformanceSummary: "EPP Desempenho · CPB on",
        presetExtremeSummary: "EPP Máximo · CPB on · sem limites",

        gamingModeTitle: "Modo Jogos",
        gamingModeHideIcon: "Ocultar ícone da barra de menus",
        gamingModeActivePreset: "Predefinição Extreme aplicada (EPP 0, CPB on)",
        gamingModeActiveKeepAwake: "Manter Ativo ligado (indefinido)",
        gamingModeIconHiddenHint: "Ícone oculto — reabra o app para abrir Ajustes",
        gamingModeC6Hint: "C6 ativo na NVRAM — use amdcstate=0 e reinicie",
        gamingModeFooter: "Um clique: aplica perfil Extreme e ativa Manter Ativo.",

        deepCStatesTitle: "Deep C-States (C6+)",
        c6ActiveBadge: "amdcstate=0 (Ativo na NVRAM)",
        c6DisabledBadge: "amdcstate=1 (Desativado - Recomendado)",
        c6Guidance: "Desativado por padrão. Recomendado OFF em PCs desktop.",

        cppcTitle: "Modo CPPC Ativo (-amdcppcactive)",
        cppcActiveBadge: "Ativo (-amdcppcactive)",
        cppcInactiveBadge: "Inativo",
        cppcGuidance: "Permite que o macOS gerencie perfis EPP em processadores AMD Zen.",

        pnopchkTitle: "Bypass de Privilégios Root (-amdpnopchk)",
        pnopchkActiveBadge: "Ativo (-amdpnopchk)",
        pnopchkInactiveBadge: "Inativo",
        pnopchkGuidance: "Permite ajustar fans e EPP sem senha de administrador.",

        copyAmdArgsButton: "Copiar Boot-Args AMD",
        copyAmdArgsGuidance: "Clique para copiar os argumentos de boot para o config.plist.",
        copiedToastText: "Copiado para a área de transferência:"
    )

    static let de = AMDPowerFeatureStrings(
        title: "AMD Ryzen Leistungssteuerung",
        modeDetectedCPPC: "Modus erkannt: CPPC (Auto-EPP)",
        modeDetectedPStates: "Modus erkannt: Legacy P-States",
        autoEPPActive: "Auto-EPP aktiv",
        energyProfileManual: "Energieprofil (Manuell)",
        autoEPPThresholds: "Auto-EPP Schwellenwerte",
        idleThresholdLabel: "Leerlauf-Schwellenwert",
        loadThresholdLabel: "Last-Schwellenwert",
        idleThresholdHelp: "Unter dieser Last % -> Energiesparen",
        loadThresholdHelp: "Über dieser Last % -> Leistung",
        advancedControls: "Erweiterte Steuerung",
        autoEPPFooter: "Auto-EPP überwacht die CPU-Auslastung und schaltet automatisch um.",
        legacyPStatesFooter: "Sperrt den P-State für globale Frequenz- und Spannungssteuerung.",
        advancedEnergyHeader: "Erweiterte Energiesteuerung",
        advancedEnergyFooter: "Deaktivieren von CPB oder Aktivieren von LPM senkt die Temperatur.",
        amdPowerControlUnsupported: "AMD Power Control wird von Ihrem Prozessor/Kext nicht unterstützt.",
        energyProfileHeader: "Energieprofil",
        perfMax: "Leistung",
        perfBalPlus: "Ausgew. Leistung",
        perfBalMinus: "Ausgew. Sparen",
        perfEco: "Energiesparen",

        cpuProfileHeader: "CPU-Profil",
        cpuProfileFooter: "Vom Kext erkannte Architektur und Energieverwaltungsfunktionen.",
        amdGPUHeader: "AMD GPU",
        amdGPUFooter: "Dedizierte AMD-GPU-Telemetrie.",

        powerPresetsHeader: "Leistungsprofile",
        powerPresetsFooter: "Ein-Klick-Profile für EPP, CPB und PPM/LPM.",
        presetsDisableAutoEppHint: "Das Anwenden eines Profils schaltet Auto-EPP aus.",
        presetEcoSummary: "Eco EPP · CPB aus · LPM an",
        presetBalanceSummary: "Ausgewogenes EPP · CPB an",
        presetPerformanceSummary: "Leistungs-EPP · CPB an",
        presetExtremeSummary: "Max EPP · CPB an · ohne Limits",

        gamingModeTitle: "Gaming-Modus",
        gamingModeHideIcon: "Menüleistensymbol ausblenden",
        gamingModeActivePreset: "Extreme-Profil angewendet",
        gamingModeActiveKeepAwake: "Wachhalten aktiv",
        gamingModeIconHiddenHint: "Symbol ausgeblendet — App neu starten für Einstellungen",
        gamingModeC6Hint: "C6 in NVRAM aktiv — amdcstate=0 setzen",
        gamingModeFooter: "Ein Klick: Extreme-Profil und Wachhalten aktivieren.",

        deepCStatesTitle: "Deep C-States (C6+)",
        c6ActiveBadge: "amdcstate=0 (NVRAM aktiv)",
        c6DisabledBadge: "amdcstate=1 (Deaktiviert - Empfohlen)",
        c6Guidance: "Standardmäßig deaktiviert. Auf Desktop-PCs empfohlen.",

        cppcTitle: "CPPC-Modus (-amdcppcactive)",
        cppcActiveBadge: "Aktiv (-amdcppcactive)",
        cppcInactiveBadge: "Inaktiv",
        cppcGuidance: "Ermöglicht macOS die Verwaltung von EPP-Profilen.",

        pnopchkTitle: "Root-Bypass (-amdpnopchk)",
        pnopchkActiveBadge: "Aktiv (-amdpnopchk)",
        pnopchkInactiveBadge: "Inaktiv",
        pnopchkGuidance: "Ermöglicht Anpassungen ohne Administratorpasswort.",

        copyAmdArgsButton: "AMD Boot-Args kopieren",
        copyAmdArgsGuidance: "Kopiert die Boot-Argumente für die config.plist.",
        copiedToastText: "In die Zwischenablage kopiert:"
    )

    static let fr = AMDPowerFeatureStrings(
        title: "Contrôle d'alimentation AMD Ryzen",
        modeDetectedCPPC: "Mode détecté : CPPC (Auto-EPP)",
        modeDetectedPStates: "Mode détecté : P-States hérités",
        autoEPPActive: "Auto-EPP actif",
        energyProfileManual: "Profil d'énergie (Manuel)",
        autoEPPThresholds: "Seuils Auto-EPP",
        idleThresholdLabel: "Seuil d'inactivité",
        loadThresholdLabel: "Seuil de charge",
        idleThresholdHelp: "En dessous de ce % de charge -> Économie d'énergie",
        loadThresholdHelp: "Au-dessus de ce % de charge -> Performance",
        advancedControls: "Contrôles avancés",
        autoEPPFooter: "Auto-EPP surveille la charge CPU et bascule entre Économie et Performance.",
        legacyPStatesFooter: "Modifie la fréquence et la tension globales en verrouillant le P-State.",
        advancedEnergyHeader: "Contrôles d'énergie avancés",
        advancedEnergyFooter: "Désactiver CPB ou activer LPM réduira la température et la consommation.",
        amdPowerControlUnsupported: "Non pris en charge sur votre processeur ou kext.",
        energyProfileHeader: "Profil d'énergie",
        perfMax: "Performance",
        perfBalPlus: "Perf. équilibrée",
        perfBalMinus: "Éco. équilibrée",
        perfEco: "Économie",

        cpuProfileHeader: "Profil CPU",
        cpuProfileFooter: "Architecture et capacités détectées par le kext.",
        amdGPUHeader: "GPU AMD",
        amdGPUFooter: "Télémétrie du GPU dédié AMD.",

        powerPresetsHeader: "Préréglages d'énergie",
        powerPresetsFooter: "Profils rapides combinant EPP, CPB et PPM/LPM.",
        presetsDisableAutoEppHint: "L'application d'un préréglage désactive l'Auto-EPP.",
        presetEcoSummary: "EPP Éco · CPB désactivé · LPM activé",
        presetBalanceSummary: "EPP Équilibré · CPB activé",
        presetPerformanceSummary: "EPP Performance · CPB activé",
        presetExtremeSummary: "EPP Max · CPB activé · sans limites",

        gamingModeTitle: "Mode Jeu",
        gamingModeHideIcon: "Masquer l'icône de la barre des menus",
        gamingModeActivePreset: "Préréglage Extreme appliqué",
        gamingModeActiveKeepAwake: "Maintien de l'éveil actif",
        gamingModeIconHiddenHint: "Icône masquée — relancez l'application pour les réglages",
        gamingModeC6Hint: "C6 actif dans la NVRAM — amdcstate=0",
        gamingModeFooter: "Un clic : active le profil Extreme et le maintien de l'éveil.",

        deepCStatesTitle: "Deep C-States (C6+)",
        c6ActiveBadge: "amdcstate=0 (NVRAM actif)",
        c6DisabledBadge: "amdcstate=1 (Désactivé - Recommandé)",
        c6Guidance: "Désactivé par défaut. Recommandé désactivé sur ordinateur de bureau.",

        cppcTitle: "Mode CPPC actif (-amdcppcactive)",
        cppcActiveBadge: "Actif (-amdcppcactive)",
        cppcInactiveBadge: "Inactif",
        cppcGuidance: "Permet à macOS de gérer les profils EPP sur processeurs Zen.",

        pnopchkTitle: "Contournement privilèges root (-amdpnopchk)",
        pnopchkActiveBadge: "Actif (-amdpnopchk)",
        pnopchkInactiveBadge: "Inactif",
        pnopchkGuidance: "Permet d'ajuster les ventilateurs et l'EPP sans mot de passe administrateur.",

        copyAmdArgsButton: "Copier les boot-args AMD",
        copyAmdArgsGuidance: "Cliquez pour copier la chaîne d'arguments pour config.plist.",
        copiedToastText: "Copié dans le presse-papiers :"
    )

    static let it = AMDPowerFeatureStrings(
        title: "Controllo Alimentazione AMD Ryzen",
        modeDetectedCPPC: "Modalità rilevata: CPPC (Auto-EPP)",
        modeDetectedPStates: "Modalità rilevata: P-States legacy",
        autoEPPActive: "Auto EPP attivo",
        energyProfileManual: "Profilo energetico (Manuale)",
        autoEPPThresholds: "Soglie Auto EPP",
        idleThresholdLabel: "Soglia inattività",
        loadThresholdLabel: "Soglia carico",
        idleThresholdHelp: "Sotto questo % di carico -> Risparmio energetico",
        loadThresholdHelp: "Sopra questo % di carico -> Prestazioni",
        advancedControls: "Controlli avanzati",
        autoEPPFooter: "Auto EPP monitora il carico CPU e commuta automaticamente tra Risparmio e Prestazioni.",
        legacyPStatesFooter: "Modifica frequenza e voltaggio bloccando il P-State.",
        advancedEnergyHeader: "Controlli energetici avanzati",
        advancedEnergyFooter: "Disattivare CPB o attivare LPM ridurrà le temperature.",
        amdPowerControlUnsupported: "Non supportato dal processore o kext.",
        energyProfileHeader: "Profilo energetico",
        perfMax: "Prestazioni",
        perfBalPlus: "Prest. bilanciate",
        perfBalMinus: "Risp. bilanciato",
        perfEco: "Risparmio",

        cpuProfileHeader: "Profilo CPU",
        cpuProfileFooter: "Architettura e funzionalità rilevate dal kext.",
        amdGPUHeader: "GPU AMD",
        amdGPUFooter: "Telemetria GPU dedicata dal kext.",

        powerPresetsHeader: "Profili preimpostati",
        powerPresetsFooter: "Profili rapidi che combinano EPP, CPB e PPM/LPM.",
        presetsDisableAutoEppHint: "L'applicazione di un profilo disattiva Auto EPP.",
        presetEcoSummary: "EPP Risparmio · CPB off · LPM on",
        presetBalanceSummary: "EPP Bilanciato · CPB on",
        presetPerformanceSummary: "EPP Prestazioni · CPB on",
        presetExtremeSummary: "EPP Max · CPB on · senza limiti",

        gamingModeTitle: "Modalità Gioco",
        gamingModeHideIcon: "Nascondi icona barra dei menu",
        gamingModeActivePreset: "Profilo Extreme applicato",
        gamingModeActiveKeepAwake: "Keep Awake attivo",
        gamingModeIconHiddenHint: "Icona nascosta — riavvia per le impostazioni",
        gamingModeC6Hint: "C6 attivo in NVRAM — amdcstate=0",
        gamingModeFooter: "Un clic: attiva il profilo Extreme e Keep Awake.",

        deepCStatesTitle: "Deep C-States (C6+)",
        c6ActiveBadge: "amdcstate=0 (NVRAM attivo)",
        c6DisabledBadge: "amdcstate=1 (Disattivato - Consigliato)",
        c6Guidance: "Disattivato per impostazione predefinita.",

        cppcTitle: "Modalità CPPC attiva (-amdcppcactive)",
        cppcActiveBadge: "Attivo (-amdcppcactive)",
        cppcInactiveBadge: "Inattivo",
        cppcGuidance: "Consente a macOS di gestire i profili EPP.",

        pnopchkTitle: "Bypass privilegi root (-amdpnopchk)",
        pnopchkActiveBadge: "Attivo (-amdpnopchk)",
        pnopchkInactiveBadge: "Inattivo",
        pnopchkGuidance: "Consente modifiche senza password di amministratore.",

        copyAmdArgsButton: "Copia boot-args AMD",
        copyAmdArgsGuidance: "Copia gli argomenti di avvio per config.plist.",
        copiedToastText: "Copiato negli appunti:"
    )

    static let ru = AMDPowerFeatureStrings(
        title: "Управление питанием AMD Ryzen",
        modeDetectedCPPC: "Режим: CPPC (Auto-EPP)",
        modeDetectedPStates: "Режим: Legacy P-States",
        autoEPPActive: "Auto EPP активен",
        energyProfileManual: "Профиль энергии (Вручную)",
        autoEPPThresholds: "Пороги Auto EPP",
        idleThresholdLabel: "Порог простоя",
        loadThresholdLabel: "Порог нагрузки",
        idleThresholdHelp: "Ниже этой нагрузки % -> Энергосбережение",
        loadThresholdHelp: "Выше этой нагрузки % -> Производительность",
        advancedControls: "Расширенные настройки",
        autoEPPFooter: "Auto EPP отслеживает нагрузку процессора и переключает профили.",
        legacyPStatesFooter: "Блокирует множитель и напряжение через P-State.",
        advancedEnergyHeader: "Расширенное питание",
        advancedEnergyFooter: "Отключение CPB или включение LPM снижает температуры.",
        amdPowerControlUnsupported: "Не поддерживается процессором или версией кекста.",
        energyProfileHeader: "Профиль энергии",
        perfMax: "Производительность",
        perfBalPlus: "Сбаланс. произв.",
        perfBalMinus: "Сбаланс. эконом.",
        perfEco: "Энергосбережение",

        cpuProfileHeader: "Профиль CPU",
        cpuProfileFooter: "Архитектура и параметры управления питанием из кекста.",
        amdGPUHeader: "AMD GPU",
        amdGPUFooter: "Телеметрия дискретной видеокарты AMD.",

        powerPresetsHeader: "Пресеты питания",
        powerPresetsFooter: "Профили в один клик: EPP, CPB и PPM/LPM.",
        presetsDisableAutoEppHint: "Применение пресета отключает Auto EPP.",
        presetEcoSummary: "Эко EPP · CPB выкл · LPM вкл",
        presetBalanceSummary: "Баланс EPP · CPB вкл",
        presetPerformanceSummary: "Производительность EPP · CPB вкл",
        presetExtremeSummary: "Макс EPP · CPB вкл · без ограничений",

        gamingModeTitle: "Игровой режим",
        gamingModeHideIcon: "Скрыть иконку в строке меню",
        gamingModeActivePreset: "Применен пресет Extreme",
        gamingModeActiveKeepAwake: "Запрет сна активен",
        gamingModeIconHiddenHint: "Иконка скрыта — перезапустите приложение для настроек",
        gamingModeC6Hint: "C6 активен в NVRAM — amdcstate=0",
        gamingModeFooter: "Один клик: включает профиль Extreme и запрет сна.",

        deepCStatesTitle: "Deep C-States (C6+)",
        c6ActiveBadge: "amdcstate=0 (Активен в NVRAM)",
        c6DisabledBadge: "amdcstate=1 (Отключен - Рекомендуется)",
        c6Guidance: "Отключен по умолчанию. Рекомендуется отключать на настольных ПК.",

        cppcTitle: "Режим CPPC (-amdcppcactive)",
        cppcActiveBadge: "Активен (-amdcppcactive)",
        cppcInactiveBadge: "Неактивен",
        cppcGuidance: "Позволяет macOS управлять профилями EPP на AMD Zen.",

        pnopchkTitle: "Обход прав root (-amdpnopchk)",
        pnopchkActiveBadge: "Активен (-amdpnopchk)",
        pnopchkInactiveBadge: "Неактивен",
        pnopchkGuidance: "Позволяет управлять вентиляторами и EPP без пароля sudo.",

        copyAmdArgsButton: "Копировать AMD Boot-Args",
        copyAmdArgsGuidance: "Копирует строку аргументов для config.plist.",
        copiedToastText: "Скопировано в буфер обмена:"
    )

    static let tr = AMDPowerFeatureStrings(
        title: "AMD Ryzen Güç Kontrolü",
        modeDetectedCPPC: "Algılanan Mod: CPPC (Auto-EPP)",
        modeDetectedPStates: "Algılanan Mod: Eski P-States",
        autoEPPActive: "Auto EPP Aktif",
        energyProfileManual: "Güç Profili (Manuel)",
        autoEPPThresholds: "Auto EPP Eşikleri",
        idleThresholdLabel: "Boşta Eşiği",
        loadThresholdLabel: "Yük Eşiği",
        idleThresholdHelp: "Bu yük % değerinin altında -> Güç Tasarrufu",
        loadThresholdHelp: "Bu yük % değerinin üstünde -> Performans",
        advancedControls: "Gelişmiş Kontroller",
        autoEPPFooter: "Auto EPP işlemci yükünü izler ve otomatik profil değiştirir.",
        legacyPStatesFooter: "P-State sabitleyerek frekans ve voltajı kilitler.",
        advancedEnergyHeader: "Gelişmiş Güç Kontrolleri",
        advancedEnergyFooter: "CPB kapatmak veya LPM açmak sıcaklıkları düşürür.",
        amdPowerControlUnsupported: "İşlemciniz veya kext sürümünüz desteklenmiyor.",
        energyProfileHeader: "Güç Profili",
        perfMax: "Performans",
        perfBalPlus: "Dengeli Perf.",
        perfBalMinus: "Dengeli Tasarruf",
        perfEco: "Güç Tasarrufu",

        cpuProfileHeader: "İşlemci Profili",
        cpuProfileFooter: "Kext tarafından algılanan mimari ve yetenekler.",
        amdGPUHeader: "AMD GPU",
        amdGPUFooter: "Kext üzerinden ayrık AMD GPU telemetrisi.",

        powerPresetsHeader: "Güç Hazır Ayarları",
        powerPresetsFooter: "EPP, CPB ve PPM/LPM birlikte uygulayan hazır profiller.",
        presetsDisableAutoEppHint: "Profil uygulamak Auto EPP'yi kapatır.",
        presetEcoSummary: "Tasarruf EPP · CPB kapalı · LPM açık",
        presetBalanceSummary: "Dengeli EPP · CPB açık",
        presetPerformanceSummary: "Performans EPP · CPB açık",
        presetExtremeSummary: "Maks EPP · CPB açık · limitsiz",

        gamingModeTitle: "Oyun Modu",
        gamingModeHideIcon: "Menü çubuğu simgesini gizle",
        gamingModeActivePreset: "Extreme profili uygulandı",
        gamingModeActiveKeepAwake: "Uyanık Tut aktif",
        gamingModeIconHiddenHint: "Simge gizli — Ayarlar için uygulamayı yeniden başlatın",
        gamingModeC6Hint: "NVRAM'de C6 aktif — amdcstate=0",
        gamingModeFooter: "Tek tık: Extreme profil ve Uyanık Tut'u açar.",

        deepCStatesTitle: "Derin C-States (C6+)",
        c6ActiveBadge: "amdcstate=0 (NVRAM Aktif)",
        c6DisabledBadge: "amdcstate=1 (Devre Dışı - Önerilen)",
        c6Guidance: "Varsayılan olarak kapalı. Masaüstü bilgisayarlarda kapalı önerilir.",

        cppcTitle: "CPPC Aktif Modu (-amdcppcactive)",
        cppcActiveBadge: "Aktif (-amdcppcactive)",
        cppcInactiveBadge: "Devre Dışı",
        cppcGuidance: "macOS'un Zen işlemcilerde EPP profillerini yönetmesini sağlar.",

        pnopchkTitle: "Root Yetki Atlama (-amdpnopchk)",
        pnopchkActiveBadge: "Aktif (-amdpnopchk)",
        pnopchkInactiveBadge: "Devre Dışı",
        pnopchkGuidance: "Yönetici şifresi olmadan fan ve EPP ayarına izin verir.",

        copyAmdArgsButton: "AMD Boot-Args Kopyala",
        copyAmdArgsGuidance: "config.plist içine yapıştırmak için argümanları kopyalar.",
        copiedToastText: "Panoya kopyalandı:"
    )

    static let ja = AMDPowerFeatureStrings(
        title: "AMD Ryzen 電源コントロール",
        modeDetectedCPPC: "検出モード: CPPC (Auto-EPP)",
        modeDetectedPStates: "検出モード: レガシー P-States",
        autoEPPActive: "Auto EPP 有効",
        energyProfileManual: "エネルギープロファイル (手動)",
        autoEPPThresholds: "Auto EPP しきい値",
        idleThresholdLabel: "アイドルしきい値",
        loadThresholdLabel: "負荷しきい値",
        idleThresholdHelp: "この負荷%未満 -> 省電力 (最大効率)",
        loadThresholdHelp: "この負荷%超 -> パフォーマンス (最大速度)",
        advancedControls: "高度なコントロール",
        autoEPPFooter: "Auto EPPはCPU負荷を監視し、省電力とパフォーマンスを自動切替します。",
        legacyPStatesFooter: "P-Stateを固定して周波数と電圧を制御します。",
        advancedEnergyHeader: "高度な電源管理",
        advancedEnergyFooter: "CPBの無効化やLPMの有効化により、温度と消費電力を抑えます。",
        amdPowerControlUnsupported: "プロセッサまたはkextのバージョンでサポートされていません。",
        energyProfileHeader: "エネルギープロファイル",
        perfMax: "パフォーマンス",
        perfBalPlus: "バランス (高)",
        perfBalMinus: "バランス (省)",
        perfEco: "省電力",

        cpuProfileHeader: "CPUプロファイル",
        cpuProfileFooter: "kextによって検出されたアーキテクチャ情報。",
        amdGPUHeader: "AMD GPU",
        amdGPUFooter: "kextからの専用AMD GPUテレメトリ。",

        powerPresetsHeader: "電源プリセット",
        powerPresetsFooter: "EPP、CPB、PPM/LPMを一括適用するワンタッププロファイル。",
        presetsDisableAutoEppHint: "プリセットを適用するとAuto EPPが無効になります。",
        presetEcoSummary: "省電力 EPP · CPB オフ · LPM オン",
        presetBalanceSummary: "バランス EPP · CPB オン",
        presetPerformanceSummary: "パフォーマンス EPP · CPB オン",
        presetExtremeSummary: "最大 EPP · CPB オン · 制限なし",

        gamingModeTitle: "ゲームモード",
        gamingModeHideIcon: "メニューバーアイコンを非表示",
        gamingModeActivePreset: "Extremeプリセット適用中",
        gamingModeActiveKeepAwake: "スリープ無効化中",
        gamingModeIconHiddenHint: "アイコン非表示中 — 設定を開くにはアプリを再起動",
        gamingModeC6Hint: "NVRAMでC6有効 — amdcstate=0",
        gamingModeFooter: "ワンクリックでExtreme設定とスリープ無効化を適用します。",

        deepCStatesTitle: "Deep C-States (C6+)",
        c6ActiveBadge: "amdcstate=0 (NVRAM 有効)",
        c6DisabledBadge: "amdcstate=1 (無効 - 推奨)",
        c6Guidance: "デフォルトで無効。デスクトップPCではOFFが推奨されます。",

        cppcTitle: "CPPCアクティブモード (-amdcppcactive)",
        cppcActiveBadge: "有効 (-amdcppcactive)",
        cppcInactiveBadge: "無効",
        cppcGuidance: "macOSがZenプロセッサのEPPプロファイルを管理できるようにします。",

        pnopchkTitle: "Root権限バイパス (-amdpnopchk)",
        pnopchkActiveBadge: "有効 (-amdpnopchk)",
        pnopchkInactiveBadge: "無効",
        pnopchkGuidance: "管理者パスワードなしでファンやEPPの調整を許可します。",

        copyAmdArgsButton: "AMD起動引数をコピー",
        copyAmdArgsGuidance: "config.plistに貼り付ける起動引数をコピーします。",
        copiedToastText: "クリップボードにコピーしました:"
    )

    static let ko = AMDPowerFeatureStrings(
        title: "AMD Ryzen 전원 제어",
        modeDetectedCPPC: "감지된 모드: CPPC (Auto-EPP)",
        modeDetectedPStates: "감지된 모드: 레거시 P-States",
        autoEPPActive: "Auto EPP 활성",
        energyProfileManual: "에너지 프로필 (수동)",
        autoEPPThresholds: "Auto EPP 임계값",
        idleThresholdLabel: "유휴 임계값",
        loadThresholdLabel: "부하 임계값",
        idleThresholdHelp: "이 부하% 미만 -> 절전 모드 (최대 효율)",
        loadThresholdHelp: "이 부하% 초과 -> 고성능 모드 (최대 속도)",
        advancedControls: "고급 제어",
        autoEPPFooter: "Auto EPP가 CPU 부하를 모니터링하여 절전과 고성능 사이를 자동 전환합니다.",
        legacyPStatesFooter: "P-State를 고정하여 주파수 및 전압을 제어합니다.",
        advancedEnergyHeader: "고급 전원 제어",
        advancedEnergyFooter: "CPB 비활성화 또는 LPM 활성화 시 발열 및 전력 소모가 감소합니다.",
        amdPowerControlUnsupported: "해당 프로세서 또는 kext 버전에서 지원되지 않습니다.",
        energyProfileHeader: "에너지 프로필",
        perfMax: "고성능",
        perfBalPlus: "균형 성능",
        perfBalMinus: "균형 절전",
        perfEco: "절전",

        cpuProfileHeader: "CPU 프로필",
        cpuProfileFooter: "kext에서 감지한 아키텍처 및 전원 관리 기능입니다.",
        amdGPUHeader: "AMD GPU",
        amdGPUFooter: "kext의 외장 AMD GPU 텔레메트리입니다.",

        powerPresetsHeader: "전원 프리셋",
        powerPresetsFooter: "EPP, CPB, PPM/LPM을 함께 적용하는 원클릭 프로필입니다.",
        presetsDisableAutoEppHint: "프리셋을 적용하면 Auto EPP가 꺼집니다.",
        presetEcoSummary: "절전 EPP · CPB 끔 · LPM 켬",
        presetBalanceSummary: "균형 EPP · CPB 켬",
        presetPerformanceSummary: "성능 EPP · CPB 켬",
        presetExtremeSummary: "최대 EPP · CPB 켬 · 제한 없음",

        gamingModeTitle: "게임 모드",
        gamingModeHideIcon: "메뉴 바 아이콘 숨기기",
        gamingModeActivePreset: "Extreme 프리셋 적용됨",
        gamingModeActiveKeepAwake: "화면 켜짐 유지 활성",
        gamingModeIconHiddenHint: "아이콘 숨김 — 설정을 열려면 앱을 다시 실행하세요",
        gamingModeC6Hint: "NVRAM C6 활성 — amdcstate=0",
        gamingModeFooter: "원클릭: Extreme 프로필 및 화면 켜짐 유지를 적용합니다.",

        deepCStatesTitle: "Deep C-States (C6+)",
        c6ActiveBadge: "amdcstate=0 (NVRAM 활성)",
        c6DisabledBadge: "amdcstate=1 (비활성 - 권장)",
        c6Guidance: "기본적으로 비활성화되어 있습니다. 데스크톱에서는 OFF를 권장합니다.",

        cppcTitle: "CPPC 활성 모드 (-amdcppcactive)",
        cppcActiveBadge: "활성 (-amdcppcactive)",
        cppcInactiveBadge: "비활성",
        cppcGuidance: "macOS가 Zen 프로세서의 EPP 프로필을 관리하도록 허용합니다.",

        pnopchkTitle: "Root 권한 우회 (-amdpnopchk)",
        pnopchkActiveBadge: "활성 (-amdpnopchk)",
        pnopchkInactiveBadge: "비활성",
        pnopchkGuidance: "관리자 암호 없이 팬 및 EPP 조절을 허용합니다.",

        copyAmdArgsButton: "AMD 부팅 플래그 복사",
        copyAmdArgsGuidance: "config.plist에 붙여넣을 부팅 플래그를 복사합니다.",
        copiedToastText: "클립보드에 복사됨:"
    )

    static let zhHans = AMDPowerFeatureStrings(
        title: "AMD Ryzen 电源控制",
        modeDetectedCPPC: "检测到模式: CPPC (Auto-EPP)",
        modeDetectedPStates: "检测到模式: 传统 P-States",
        autoEPPActive: "Auto EPP 运行中",
        energyProfileManual: "能效配置文件 (手动)",
        autoEPPThresholds: "Auto EPP 阈值",
        idleThresholdLabel: "空闲阈值",
        loadThresholdLabel: "负载阈值",
        idleThresholdHelp: "低于此负载% -> 节能 (最高能效)",
        loadThresholdHelp: "高于此负载% -> 性能 (最高速度)",
        advancedControls: "高级控制",
        autoEPPFooter: "Auto EPP 监控 CPU 负载并在节能与高性能之间自动切换。",
        legacyPStatesFooter: "通过锁定 P-State 来调整全局频率与电压。",
        advancedEnergyHeader: "高级电源控制",
        advancedEnergyFooter: "禁用 CPB 或启用 LPM 可降低温度和功耗。",
        amdPowerControlUnsupported: "您的处理器或 kext 版本不支持 AMD 电源控制。",
        energyProfileHeader: "能效配置文件",
        perfMax: "高性能",
        perfBalPlus: "均衡性能",
        perfBalMinus: "均衡节能",
        perfEco: "节能",

        cpuProfileHeader: "CPU 信息",
        cpuProfileFooter: "kext 检测到的架构和电源管理功能。",
        amdGPUHeader: "AMD GPU",
        amdGPUFooter: "kext 提供的 AMD 独显遥测数据。",

        powerPresetsHeader: "电源预设",
        powerPresetsFooter: "一键配置 EPP、CPB 和 PPM/LPM 的整合配置文件。",
        presetsDisableAutoEppHint: "应用预设会关闭 Auto EPP 以保持配置。",
        presetEcoSummary: "节能 EPP · CPB 关闭 · LPM 开启",
        presetBalanceSummary: "均衡 EPP · CPB 开启",
        presetPerformanceSummary: "性能 EPP · CPB 开启",
        presetExtremeSummary: "极限 EPP · CPB 开启 · 无限制",

        gamingModeTitle: "游戏模式",
        gamingModeHideIcon: "隐藏菜单栏图标",
        gamingModeActivePreset: "已应用 Extreme 预设",
        gamingModeActiveKeepAwake: "防休眠已激活",
        gamingModeIconHiddenHint: "图标已隐藏 — 重新启动应用以打开设置",
        gamingModeC6Hint: "NVRAM 中 C6 仍启用 — 设置 amdcstate=0",
        gamingModeFooter: "一键应用 Extreme 配置文件并保持唤醒状态。",

        deepCStatesTitle: "深度 C-States (C6+)",
        c6ActiveBadge: "amdcstate=0 (NVRAM 已启用)",
        c6DisabledBadge: "amdcstate=1 (已禁用 - 推荐)",
        c6Guidance: "默认禁用。台式机建议保持关闭以避免唤醒延迟。",

        cppcTitle: "CPPC 活动模式 (-amdcppcactive)",
        cppcActiveBadge: "已激活 (-amdcppcactive)",
        cppcInactiveBadge: "未激活",
        cppcGuidance: "允许 macOS 在 AMD Zen 处理器上管理 EPP 配置文件。",

        pnopchkTitle: "Root 权限绕过 (-amdpnopchk)",
        pnopchkActiveBadge: "已激活 (-amdpnopchk)",
        pnopchkInactiveBadge: "未激活",
        pnopchkGuidance: "允许在不输入密码的情况下调整风扇和 EPP。",

        copyAmdArgsButton: "复制 AMD 引导参数",
        copyAmdArgsGuidance: "复制用于粘贴到 config.plist 的 AMD 引导参数字符串。",
        copiedToastText: "已复制到剪贴板:"
    )

    static let zhTW = AMDPowerFeatureStrings(
        title: "AMD Ryzen 電源控制",
        modeDetectedCPPC: "偵測到模式: CPPC (Auto-EPP)",
        modeDetectedPStates: "偵測到模式: 傳統 P-States",
        autoEPPActive: "Auto EPP 啟用中",
        energyProfileManual: "能源設定檔 (手動)",
        autoEPPThresholds: "Auto EPP 閾值",
        idleThresholdLabel: "閒置閾值",
        loadThresholdLabel: "負載閾值",
        idleThresholdHelp: "低於此負載% -> 省電 (最高能效)",
        loadThresholdHelp: "高於此負載% -> 效能 (最高速度)",
        advancedControls: "進階控制",
        autoEPPFooter: "Auto EPP 監控 CPU 負載並在省電與高效能間自動切換。",
        legacyPStatesFooter: "鎖定 P-State 調整全域頻率與電壓。",
        advancedEnergyHeader: "進階電源控制",
        advancedEnergyFooter: "停用 CPB 或啟用 LPM 可降低溫度與功耗。",
        amdPowerControlUnsupported: "您的處理器或 kext 版本不支援 AMD 電源控制。",
        energyProfileHeader: "能源設定檔",
        perfMax: "高效能",
        perfBalPlus: "均衡效能",
        perfBalMinus: "均衡省電",
        perfEco: "省電",

        cpuProfileHeader: "CPU 資訊",
        cpuProfileFooter: "kext 偵測到的架構與電源管理功能。",
        amdGPUHeader: "AMD GPU",
        amdGPUFooter: "kext 提供的 AMD 獨立顯示卡遙測。",

        powerPresetsHeader: "電源預設",
        powerPresetsFooter: "一鍵設定 EPP、CPB 與 PPM/LPM 的整合設定檔。",
        presetsDisableAutoEppHint: "套用預設會關閉 Auto EPP 以維持設定。",
        presetEcoSummary: "省電 EPP · CPB 關閉 · LPM 開啟",
        presetBalanceSummary: "均衡 EPP · CPB 開啟",
        presetPerformanceSummary: "效能 EPP · CPB 開啟",
        presetExtremeSummary: "極限 EPP · CPB 開啟 · 無限制",

        gamingModeTitle: "遊戲模式",
        gamingModeHideIcon: "隱藏選單列圖示",
        gamingModeActivePreset: "已套用 Extreme 預設",
        gamingModeActiveKeepAwake: "防休眠已啟用",
        gamingModeIconHiddenHint: "圖示已隱藏 — 重新啟動 App 以開啟設定",
        gamingModeC6Hint: "NVRAM 中 C6 仍啟用 — 設定 amdcstate=0",
        gamingModeFooter: "一鍵套用 Extreme 設定檔並保持喚醒。",

        deepCStatesTitle: "深度 C-States (C6+)",
        c6ActiveBadge: "amdcstate=0 (NVRAM 已啟用)",
        c6DisabledBadge: "amdcstate=1 (已停用 - 建議)",
        c6Guidance: "預設停用。桌上型電腦建議保持關閉以避免喚醒延遲。",

        cppcTitle: "CPPC 活動模式 (-amdcppcactive)",
        cppcActiveBadge: "已啟用 (-amdcppcactive)",
        cppcInactiveBadge: "未啟用",
        cppcGuidance: "允許 macOS 在 AMD Zen 處理器上管理 EPP 設定檔。",

        pnopchkTitle: "Root 權限繞過 (-amdpnopchk)",
        pnopchkActiveBadge: "已啟用 (-amdpnopchk)",
        pnopchkInactiveBadge: "未啟用",
        pnopchkGuidance: "允許在無需密碼的情況下調整風扇與 EPP。",

        copyAmdArgsButton: "複製 AMD 開機參數",
        copyAmdArgsGuidance: "複製用於貼至 config.plist 的 AMD 開機參數字串。",
        copiedToastText: "已複製至剪貼簿:"
    )

    static let zhHK = zhTW
}
