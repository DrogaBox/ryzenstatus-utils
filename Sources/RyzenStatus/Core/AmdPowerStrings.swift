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
}
