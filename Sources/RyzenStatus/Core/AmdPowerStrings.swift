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
        perfEco: "Power Save"
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
        perfEco: "Ahorro Máx."
    )
}
