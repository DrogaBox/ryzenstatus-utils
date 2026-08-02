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

extension AMDPowerFeatureStrings {
    static func current(_ language: AppLanguage) -> AMDPowerFeatureStrings {
        switch language {
        case .es: return .es
        default: return .enUS
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
}
