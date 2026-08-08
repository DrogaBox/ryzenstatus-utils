// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

extension DefaultsKey {
    // System monitor — live metrics shown next to the menu bar icon (opt-in).
    static let monitorGraphCPUMode = "monitorGraphCPUMode"
    static let menuBarCPU = "menuBarCPU"
    static let menuBarGPU = "menuBarGPU"
    static let menuBarCPUPower = "menuBarCPUPower"
    static let menuBarGPUPower = "menuBarGPUPower"
    static let menuBarCPUFrequency = "menuBarCPUFrequency"
    static let menuBarCPUTempPower = "menuBarCPUTempPower"
    static let menuBarGPUTempPower = "menuBarGPUTempPower"
    static let menuBarMemory = "menuBarMemory"
    static let menuBarCPUTemperature = "menuBarCPUTemperature"
    static let menuBarGPUTemperature = "menuBarGPUTemperature"
    static let menuBarBatteryTemperature = "menuBarBatteryTemperature"
    static let menuBarTemperature = "menuBarTemperature" // legacy Developer key for the old generic temperature metric
    static let menuBarNetwork = "menuBarNetwork"
    static let menuBarDiskUsage = "menuBarDiskUsage"
    static let menuBarDiskActivity = "menuBarDiskActivity"
    static let menuBarBattery = "menuBarBattery"
    static let menuBarBatteryTime = "menuBarBatteryTime"
    static let menuBarPeripheralBattery = "menuBarPeripheralBattery"
    static let menuBarPower = "menuBarPower"
    static let menuBarPreset = "menuBarPreset"           // dense
    static let menuBarMetricSpacing = "menuBarMetricSpacing" // standard | compact
    static let menuBarMetricAppearance = "menuBarMetricAppearance" // values | bars
    static let menuBarUsageBarNormalColor = "menuBarUsageBarNormalColor" // #RRGGBB
    static let menuBarUsageBarElevatedColor = "menuBarUsageBarElevatedColor" // #RRGGBB
    static let menuBarUsageBarCriticalColor = "menuBarUsageBarCriticalColor" // #RRGGBB
    static let menuBarUsageBarMediumThreshold = "menuBarUsageBarMediumThreshold" // percent
    static let menuBarUsageBarHighThreshold = "menuBarUsageBarHighThreshold" // percent
    static let menuBarHideIconWithMetrics = "menuBarHideIconWithMetrics" // glyph hides while metrics render in the main item
    static let menuBarGraphShowsValue = "menuBarGraphShowsValue" // render numeric text inside graph blocks
    static let menuBarMetricOrder = "menuBarMetricOrder" // comma-separated MenuBarMetric raw values
    static let menuBarCombineTemperatures = "menuBarCombineTemperatures" // usage/charge + temperature in one block when possible
    static let menuBarSeparateMetrics = "menuBarSeparateMetrics" // one status item per active metric
    static let menuBarSeparateMetricsCaptionVisible = "menuBarSeparateMetricsCaptionVisible"
    static let menuBarLayoutMode = "menuBarLayoutMode" // classic | modern
    static let menuBarNetworkUploadFirst = "menuBarNetworkUploadFirst" // network menu bar block shows upload above download
    static let menuBarLabelStyle = "menuBarLabelStyle"     // compact | classic
    static let menuBarMemoryStyle = "menuBarMemoryStyle"   // dot | percent | both
    static let monitorInterval = "monitorIntervalSeconds"  // sampling cadence: 1/2/5
    // System monitor — which blocks appear in the panel.
    static let monitorShowSystem = "monitorShowSystem"
    static let monitorShowNetwork = "monitorShowNetwork"
    static let monitorShowDisk = "monitorShowDisk"
    static let monitorShowPower = "monitorShowPower"
    static let monitorShowMixer = "monitorShowMixer"
    static let monitorShowFanControlBeta = "monitorShowFanControlBeta"
    // System monitor — per-metric history graphs (each independently toggleable).
    static let monitorGraphCPU = "monitorGraphCPU"
    static let monitorGraphGPU = "monitorGraphGPU"
    static let monitorGraphMemory = "monitorGraphMemory"
    static let monitorGraphNetwork = "monitorGraphNetwork"
    static let monitorGraphDisk = "monitorGraphDisk"
    static let monitorGraphPower = "monitorGraphPower"
    static let monitorGraphBattery = "monitorGraphBattery"
    // System monitor — per-item visibility inside each panel section.
    static let monitorSysTemps = "monitorSysTemps"
    static let monitorSysCPU = "monitorSysCPU"
    static let monitorSysGPU = "monitorSysGPU"
    static let monitorSysBattery = "monitorSysBattery"
    static let monitorSysMemory = "monitorSysMemory"
    static let monitorSysAlerts = "monitorSysAlerts"
    static let monitorSysUptime = "monitorSysUptime"
    static let monitorNetSpeed = "monitorNetSpeed"
    static let monitorNetApps = "monitorNetApps"
    static let monitorNetTotals = "monitorNetTotals"
    static let monitorNetTest = "monitorNetTest"
    static let monitorDiskUsage = "monitorDiskUsage"
    static let monitorDiskActivity = "monitorDiskActivity"
    static let monitorDiskSMART = "monitorDiskSMART"
    static let monitorDiskProtection = "monitorDiskProtection"
    static let monitorDiskTools = "monitorDiskTools"
    static let monitorPwrSystem = "monitorPwrSystem"
    static let monitorPwrAdapter = "monitorPwrAdapter"
    static let monitorPwrBattery = "monitorPwrBattery"
    static let monitorPwrTimeRemaining = "monitorPwrTimeRemaining"
    static let monitorPwrHealth = "monitorPwrHealth"
    // System monitor — optional notifications for sustained or actionable conditions.
    static let monitorAlertCPU = "monitorAlertCPU"
    static let monitorAlertCPUTemperature = "monitorAlertCPUTemperature"
    static let monitorAlertGPUTemperature = "monitorAlertGPUTemperature"
    static let monitorAlertGPUPower = "monitorAlertGPUPower"
    static let monitorAlertMemory = "monitorAlertMemory"
    static let monitorAlertDisk = "monitorAlertDisk"
    static let monitorAlertBattery = "monitorAlertBattery"
    static let monitorAlertCPUThreshold = "monitorAlertCPUThreshold"
    static let monitorAlertCPUTemperatureThreshold = "monitorAlertCPUTemperatureThreshold"
    static let monitorAlertGPUTemperatureThreshold = "monitorAlertGPUTemperatureThreshold"
    static let monitorAlertGPUPowerThreshold = "monitorAlertGPUPowerThreshold"
    static let monitorAlertDiskFreePercent = "monitorAlertDiskFreePercent"
    static let monitorAlertBatteryPercent = "monitorAlertBatteryPercent"
    static let monitorAlertCooldownMinutes = "monitorAlertCooldownMinutes"
}
