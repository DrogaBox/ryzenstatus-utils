// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import IOKit

/// Strings for the Performance Suite dashboard, its process manager, the
/// AMD write status lines and the fan curve editor's prompts. Technical
/// tokens (CPU, GPU, VRAM, PID, SMU, OC, C0, CC6, MHz, °C) stay untranslated
/// by the AMD string convention; every sentence is localized.
struct DashboardFeatureStrings {
    /// CPU box headline: whole-CPU load.
    let totalUtilization: String
    /// Short stat badge label.
    let temperatureShort: String
    /// Short stat badge label.
    let frequencyShort: String
    /// Short stat badge label.
    let powerShort: String
    /// Box title.
    let memoryAndStorage: String
    /// Row label.
    let diskIO: String
    /// Two %@ rates: read, then write.
    let diskReadWriteFormat: String
    /// Box title.
    let networkTraffic: String
    /// Box title.
    let processManager: String
    /// Label before the sort picker.
    let sortBy: String
    /// Table header: the sorted resource value.
    let usageColumn: String
    /// One %d: rows shown.
    let processCountFormat: String
    let loadingProcesses: String
    let noGPUProcesses: String
    /// Short button in a 60 pt cell; ends the process.
    let killShort: String
    /// Two %d: physical cores, logical threads.
    let cpuTopologyFormat: String
    /// One %@: a percentage such as 42%.
    let memoryUsedPercentFormat: String
    /// One %@: a size such as 32 GB.
    let memoryTotalFormat: String
    /// One %@: a size such as 16 GB.
    let vramTotalFormat: String
    /// One %@: a temperature.
    let hottestCoreFormat: String
    let fabricClocksTitle: String
    /// Legend for a dash shown on a sleeping core.
    let coreParkedLegend: String
    let pmVoltageHelp: String
    let pmC0Help: String
    let pmCC6Help: String
    /// Chart title: GPU load history.
    let gpuCompute: String
    /// One %@: the average.
    let averageFormat: String
    /// Spoken chart summary; three %@: average, peak, latest.
    let chartSummaryFormat: String
    /// One %@: an IP address.
    let ipAddressFormat: String
    let categorySystem: String
    let categoryApp: String
    let categoryHelper: String
    let categoryBackground: String
    let categoryDeveloper: String
    let categorySecurity: String
    let statusRequiresRoot: String
    let statusNotSupported: String
    /// The kext refuses above 75 °C and while it is not ready.
    let statusNotReady: String
    let statusSmuRejected: String
    let statusSmuTimeout: String
    let statusSmuBusy: String
    let statusOutOfRange: String
    let statusInvalidCore: String
    let statusInvalidFrequency: String
    let statusInvalidOcMode: String
    let statusEnableOcFirst: String
    /// One %08X: the kext's return code.
    let statusFailedCodeFormat: String
    /// One %d: core number from 1.
    let coreLabelFormat: String
    /// Two %d: core number, new offset.
    let coreOffsetAppliedFormat: String
    /// One %d: cores written.
    let coresAppliedFormat: String
    /// VoiceOver label; one %d: core number.
    let coLowerFormat: String
    /// VoiceOver label; one %d: core number.
    let coRaiseFormat: String
    let pmCaptureFailed: String
    let exportFailed: String
    let discardChangesTitle: String
    let discardChangesButton: String
    let deleteCurveInUseTitle: String
    let deleteCurveInUseMessage: String
    let curveRejectedHint: String
    /// VoiceOver label; one %d: point number.
    let curvePointLabelFormat: String
    /// VoiceOver value; two %d: °C, duty percent.
    let curvePointValueFormat: String
    /// One %d: the minimum duty percent.
    let pwmFloorFormat: String
    let unknownCurve: String
    /// Refresh interval option.
    let intervalThreeSeconds: String
}

extension DashboardFeatureStrings {
    static func current(_ language: AppLanguage) -> DashboardFeatureStrings {
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
        case .sk: return .sk
        case .uk: return .uk
        }
    }
}

extension FeatureStrings {
    static func dashboard(_ language: AppLanguage) -> DashboardFeatureStrings {
        DashboardFeatureStrings.current(language)
    }
}

extension L10n {
    var dashboard: DashboardFeatureStrings {
        FeatureStrings.dashboard(language)
    }
}

/// The one line shown under a control when a kext write fails. A refusal
/// code means different things per control, so the caller can name what a
/// bad argument or a refused write means there.
enum AmdWriteStatus {
    static func text(_ status: kern_return_t, strings: DashboardFeatureStrings,
                     badArgument: String? = nil, notPermitted: String? = nil) -> String {
        switch status {
        case ProcessorModel.kIOReturnNotPrivilegedCode: return strings.statusRequiresRoot
        case kIOReturnUnsupported: return strings.statusNotSupported
        // Above 75 °C, but also while the driver is not ready or stopping.
        case kIOReturnNotReady: return strings.statusNotReady
        case kIOReturnNotPermitted: return notPermitted ?? strings.statusSmuRejected
        case kIOReturnBadArgument: return badArgument ?? strings.statusOutOfRange
        case kIOReturnTimeout: return strings.statusSmuTimeout
        case kIOReturnBusy: return strings.statusSmuBusy
        default: return String(format: strings.statusFailedCodeFormat, UInt32(bitPattern: status))
        }
    }
}

extension DashboardFeatureStrings {
    static let enUS = DashboardFeatureStrings(
        totalUtilization: "Total utilization",
        temperatureShort: "Temp",
        frequencyShort: "Freq",
        powerShort: "Power",
        memoryAndStorage: "Memory & storage",
        diskIO: "Disk I/O",
        diskReadWriteFormat: "R %@  W %@",
        networkTraffic: "Network traffic",
        processManager: "Process manager",
        sortBy: "Sort by:",
        usageColumn: "Usage",
        processCountFormat: "Processes: %d",
        loadingProcesses: "Loading processes…",
        noGPUProcesses: "This GPU reports no per-process GPU time.",
        killShort: "Kill",
        cpuTopologyFormat: "Cores: %d · Threads: %d",
        memoryUsedPercentFormat: "%@ used",
        memoryTotalFormat: "%@ total",
        vramTotalFormat: "%@ VRAM",
        hottestCoreFormat: "Hottest core %@",
        fabricClocksTitle: "Fabric (MHz)",
        coreParkedLegend: "— parked",
        pmVoltageHelp: "Per-core voltage (SMU)",
        pmC0Help: "C0 residency (%)",
        pmCC6Help: "CC6 residency (%)",
        gpuCompute: "GPU compute",
        averageFormat: "Avg %@",
        chartSummaryFormat: "Average %@, peak %@, latest %@",
        ipAddressFormat: "IP: %@",
        categorySystem: "System",
        categoryApp: "App",
        categoryHelper: "Helper",
        categoryBackground: "Background",
        categoryDeveloper: "Developer",
        categorySecurity: "Security",
        statusRequiresRoot: "Requires root or -amdpnopchk",
        statusNotSupported: "Not supported by the kext on this CPU",
        statusNotReady: "Refused: package above 75 °C, or the driver is not ready",
        statusSmuRejected: "The SMU refused the change",
        statusSmuTimeout: "SMU timeout — try again",
        statusSmuBusy: "SMU busy — try again",
        statusOutOfRange: "Value outside the safe range",
        statusInvalidCore: "Invalid core index",
        statusInvalidFrequency: "Invalid frequency request",
        statusInvalidOcMode: "Invalid OC mode request",
        statusEnableOcFirst: "Enable OC mode first (this driver must open the gate itself)",
        statusFailedCodeFormat: "Failed (0x%08X)",
        coreLabelFormat: "Core %d",
        coreOffsetAppliedFormat: "Core %d → %d",
        coresAppliedFormat: "Cores written: %d",
        coLowerFormat: "Lower core %d offset",
        coRaiseFormat: "Raise core %d offset",
        pmCaptureFailed: "PM table capture failed",
        exportFailed: "Export failed",
        discardChangesTitle: "Discard unsaved curve changes?",
        discardChangesButton: "Discard",
        deleteCurveInUseTitle: "Delete a curve in use?",
        deleteCurveInUseMessage: "Fans that follow this curve go back to BIOS control.",
        curveRejectedHint: "The curve was not saved: check its points.",
        curvePointLabelFormat: "Curve point %d",
        curvePointValueFormat: "%d °C, %d%% duty",
        pwmFloorFormat: "%d%% floor",
        unknownCurve: "Unknown",
        intervalThreeSeconds: "3 seconds"
    )
}

extension DashboardFeatureStrings {
    static let ptBR = DashboardFeatureStrings(
        totalUtilization: "Uso total",
        temperatureShort: "Temp",
        frequencyShort: "Freq",
        powerShort: "Energia",
        memoryAndStorage: "Memória e armazenamento",
        diskIO: "E/S de disco",
        diskReadWriteFormat: "L %@  G %@",
        networkTraffic: "Tráfego de rede",
        processManager: "Gerenciador de processos",
        sortBy: "Ordenar por:",
        usageColumn: "Uso",
        processCountFormat: "Processos: %d",
        loadingProcesses: "Carregando processos…",
        noGPUProcesses: "Esta GPU não informa tempo de GPU por processo.",
        killShort: "Encerrar",
        cpuTopologyFormat: "Núcleos: %d · Threads: %d",
        memoryUsedPercentFormat: "%@ em uso",
        memoryTotalFormat: "%@ no total",
        vramTotalFormat: "%@ de VRAM",
        hottestCoreFormat: "Núcleo mais quente %@",
        fabricClocksTitle: "Fabric (MHz)",
        coreParkedLegend: "— em repouso",
        pmVoltageHelp: "Tensão por núcleo (SMU)",
        pmC0Help: "Residência em C0 (%)",
        pmCC6Help: "Residência em CC6 (%)",
        gpuCompute: "Computação da GPU",
        averageFormat: "Média %@",
        chartSummaryFormat: "Média %@, pico %@, último %@",
        ipAddressFormat: "IP: %@",
        categorySystem: "Sistema",
        categoryApp: "App",
        categoryHelper: "Auxiliar",
        categoryBackground: "Segundo plano",
        categoryDeveloper: "Desenvolvedor",
        categorySecurity: "Segurança",
        statusRequiresRoot: "Requer root ou -amdpnopchk",
        statusNotSupported: "Não suportado pelo kext nesta CPU",
        statusNotReady: "Recusado: pacote acima de 75 °C ou driver não pronto",
        statusSmuRejected: "A SMU recusou a alteração",
        statusSmuTimeout: "Tempo esgotado na SMU — tente de novo",
        statusSmuBusy: "SMU ocupada — tente de novo",
        statusOutOfRange: "Valor fora da faixa segura",
        statusInvalidCore: "Índice de núcleo inválido",
        statusInvalidFrequency: "Pedido de frequência inválido",
        statusInvalidOcMode: "Pedido de modo OC inválido",
        statusEnableOcFirst: "Ative o modo OC primeiro (este driver precisa abrir o acesso)",
        statusFailedCodeFormat: "Falhou (0x%08X)",
        coreLabelFormat: "Núcleo %d",
        coreOffsetAppliedFormat: "Núcleo %d → %d",
        coresAppliedFormat: "Núcleos gravados: %d",
        coLowerFormat: "Diminuir offset do núcleo %d",
        coRaiseFormat: "Aumentar offset do núcleo %d",
        pmCaptureFailed: "Falha ao capturar a tabela PM",
        exportFailed: "Falha ao exportar",
        discardChangesTitle: "Descartar alterações não salvas da curva?",
        discardChangesButton: "Descartar",
        deleteCurveInUseTitle: "Apagar uma curva em uso?",
        deleteCurveInUseMessage: "As ventoinhas que seguem esta curva voltam ao controle da BIOS.",
        curveRejectedHint: "A curva não foi salva: verifique os pontos.",
        curvePointLabelFormat: "Ponto da curva %d",
        curvePointValueFormat: "%d °C, %d%% de ciclo",
        pwmFloorFormat: "Mínimo %d%%",
        unknownCurve: "Desconhecida",
        intervalThreeSeconds: "3 segundos"
    )
}

extension DashboardFeatureStrings {
    static let tr = DashboardFeatureStrings(
        totalUtilization: "Toplam kullanım",
        temperatureShort: "Sıcaklık",
        frequencyShort: "Frekans",
        powerShort: "Güç",
        memoryAndStorage: "Bellek ve depolama",
        diskIO: "Disk G/Ç",
        diskReadWriteFormat: "O %@  Y %@",
        networkTraffic: "Ağ trafiği",
        processManager: "İşlem yöneticisi",
        sortBy: "Sırala:",
        usageColumn: "Kullanım",
        processCountFormat: "İşlemler: %d",
        loadingProcesses: "İşlemler yükleniyor…",
        noGPUProcesses: "Bu GPU işlem başına GPU süresi bildirmiyor.",
        killShort: "Sonlandır",
        cpuTopologyFormat: "Çekirdek: %d · İş parçacığı: %d",
        memoryUsedPercentFormat: "%@ kullanımda",
        memoryTotalFormat: "Toplam %@",
        vramTotalFormat: "%@ VRAM",
        hottestCoreFormat: "En sıcak çekirdek %@",
        fabricClocksTitle: "Fabric (MHz)",
        coreParkedLegend: "— uykuda",
        pmVoltageHelp: "Çekirdek başına voltaj (SMU)",
        pmC0Help: "C0 kalış oranı (%)",
        pmCC6Help: "CC6 kalış oranı (%)",
        gpuCompute: "GPU hesaplama",
        averageFormat: "Ort. %@",
        chartSummaryFormat: "Ortalama %@, tepe %@, son %@",
        ipAddressFormat: "IP: %@",
        categorySystem: "Sistem",
        categoryApp: "Uygulama",
        categoryHelper: "Yardımcı",
        categoryBackground: "Arka plan",
        categoryDeveloper: "Geliştirici",
        categorySecurity: "Güvenlik",
        statusRequiresRoot: "Root veya -amdpnopchk gerekir",
        statusNotSupported: "Bu CPU'da kext tarafından desteklenmiyor",
        statusNotReady: "Reddedildi: paket 75 °C üzerinde veya sürücü hazır değil",
        statusSmuRejected: "SMU değişikliği reddetti",
        statusSmuTimeout: "SMU zaman aşımı — yeniden deneyin",
        statusSmuBusy: "SMU meşgul — yeniden deneyin",
        statusOutOfRange: "Değer güvenli aralığın dışında",
        statusInvalidCore: "Geçersiz çekirdek numarası",
        statusInvalidFrequency: "Geçersiz frekans isteği",
        statusInvalidOcMode: "Geçersiz OC modu isteği",
        statusEnableOcFirst: "Önce OC modunu açın (bu sürücü kapıyı kendisi açmalı)",
        statusFailedCodeFormat: "Başarısız (0x%08X)",
        coreLabelFormat: "Çekirdek %d",
        coreOffsetAppliedFormat: "Çekirdek %d → %d",
        coresAppliedFormat: "Yazılan çekirdek: %d",
        coLowerFormat: "Çekirdek %d ofsetini düşür",
        coRaiseFormat: "Çekirdek %d ofsetini artır",
        pmCaptureFailed: "PM tablosu alınamadı",
        exportFailed: "Dışa aktarma başarısız",
        discardChangesTitle: "Kaydedilmemiş eğri değişiklikleri atılsın mı?",
        discardChangesButton: "At",
        deleteCurveInUseTitle: "Kullanımdaki bir eğri silinsin mi?",
        deleteCurveInUseMessage: "Bu eğriyi izleyen fanlar BIOS denetimine döner.",
        curveRejectedHint: "Eğri kaydedilmedi: noktalarını kontrol edin.",
        curvePointLabelFormat: "Eğri noktası %d",
        curvePointValueFormat: "%d °C, %%%d görev",
        pwmFloorFormat: "En az %%%d",
        unknownCurve: "Bilinmiyor",
        intervalThreeSeconds: "3 saniye"
    )
}

extension DashboardFeatureStrings {
    static let ru = DashboardFeatureStrings(
        totalUtilization: "Общая загрузка",
        temperatureShort: "Темп.",
        frequencyShort: "Частота",
        powerShort: "Мощность",
        memoryAndStorage: "Память и накопители",
        diskIO: "Диск: ввод-вывод",
        diskReadWriteFormat: "Чт %@  Зап %@",
        networkTraffic: "Сетевой трафик",
        processManager: "Диспетчер процессов",
        sortBy: "Сортировка:",
        usageColumn: "Нагрузка",
        processCountFormat: "Процессов: %d",
        loadingProcesses: "Загрузка процессов…",
        noGPUProcesses: "Этот GPU не сообщает время GPU по процессам.",
        killShort: "Завершить",
        cpuTopologyFormat: "Ядер: %d · Потоков: %d",
        memoryUsedPercentFormat: "Занято %@",
        memoryTotalFormat: "Всего %@",
        vramTotalFormat: "VRAM %@",
        hottestCoreFormat: "Самое горячее ядро %@",
        fabricClocksTitle: "Fabric (МГц)",
        coreParkedLegend: "— в простое",
        pmVoltageHelp: "Напряжение по ядрам (SMU)",
        pmC0Help: "Доля в C0 (%)",
        pmCC6Help: "Доля в CC6 (%)",
        gpuCompute: "Вычисления GPU",
        averageFormat: "Сред. %@",
        chartSummaryFormat: "Среднее %@, пик %@, последнее %@",
        ipAddressFormat: "IP: %@",
        categorySystem: "Система",
        categoryApp: "Приложение",
        categoryHelper: "Помощник",
        categoryBackground: "Фоновый",
        categoryDeveloper: "Разработка",
        categorySecurity: "Безопасность",
        statusRequiresRoot: "Нужны права root или -amdpnopchk",
        statusNotSupported: "Kext не поддерживает это на данном CPU",
        statusNotReady: "Отказано: корпус выше 75 °C или драйвер не готов",
        statusSmuRejected: "SMU отклонил изменение",
        statusSmuTimeout: "Тайм-аут SMU — попробуйте снова",
        statusSmuBusy: "SMU занят — попробуйте снова",
        statusOutOfRange: "Значение вне безопасного диапазона",
        statusInvalidCore: "Неверный номер ядра",
        statusInvalidFrequency: "Неверный запрос частоты",
        statusInvalidOcMode: "Неверный запрос режима OC",
        statusEnableOcFirst: "Сначала включите режим OC (драйвер должен сам открыть доступ)",
        statusFailedCodeFormat: "Ошибка (0x%08X)",
        coreLabelFormat: "Ядро %d",
        coreOffsetAppliedFormat: "Ядро %d → %d",
        coresAppliedFormat: "Записано ядер: %d",
        coLowerFormat: "Уменьшить смещение ядра %d",
        coRaiseFormat: "Увеличить смещение ядра %d",
        pmCaptureFailed: "Не удалось снять таблицу PM",
        exportFailed: "Не удалось экспортировать",
        discardChangesTitle: "Отменить несохранённые изменения кривой?",
        discardChangesButton: "Отменить изменения",
        deleteCurveInUseTitle: "Удалить используемую кривую?",
        deleteCurveInUseMessage: "Вентиляторы, работающие по этой кривой, вернутся под управление BIOS.",
        curveRejectedHint: "Кривая не сохранена: проверьте её точки.",
        curvePointLabelFormat: "Точка кривой %d",
        curvePointValueFormat: "%d °C, скважность %d%%",
        pwmFloorFormat: "Минимум %d%%",
        unknownCurve: "Неизвестно",
        intervalThreeSeconds: "3 секунды"
    )
}

extension DashboardFeatureStrings {
    static let es = DashboardFeatureStrings(
        totalUtilization: "Uso total",
        temperatureShort: "Temp",
        frequencyShort: "Frec",
        powerShort: "Potencia",
        memoryAndStorage: "Memoria y almacenamiento",
        diskIO: "E/S de disco",
        diskReadWriteFormat: "L %@  E %@",
        networkTraffic: "Tráfico de red",
        processManager: "Gestor de procesos",
        sortBy: "Ordenar por:",
        usageColumn: "Uso",
        processCountFormat: "Procesos: %d",
        loadingProcesses: "Cargando procesos…",
        noGPUProcesses: "Esta GPU no informa tiempo de GPU por proceso.",
        killShort: "Terminar",
        cpuTopologyFormat: "Núcleos: %d · Hilos: %d",
        memoryUsedPercentFormat: "%@ en uso",
        memoryTotalFormat: "%@ en total",
        vramTotalFormat: "%@ de VRAM",
        hottestCoreFormat: "Núcleo más caliente %@",
        fabricClocksTitle: "Fabric (MHz)",
        coreParkedLegend: "— en reposo",
        pmVoltageHelp: "Voltaje por núcleo (SMU)",
        pmC0Help: "Residencia en C0 (%)",
        pmCC6Help: "Residencia en CC6 (%)",
        gpuCompute: "Cómputo de GPU",
        averageFormat: "Media %@",
        chartSummaryFormat: "Media %@, pico %@, último %@",
        ipAddressFormat: "IP: %@",
        categorySystem: "Sistema",
        categoryApp: "App",
        categoryHelper: "Auxiliar",
        categoryBackground: "Segundo plano",
        categoryDeveloper: "Desarrollo",
        categorySecurity: "Seguridad",
        statusRequiresRoot: "Requiere root o -amdpnopchk",
        statusNotSupported: "El kext no lo admite en esta CPU",
        statusNotReady: "Rechazado: paquete por encima de 75 °C o el driver no está listo",
        statusSmuRejected: "La SMU rechazó el cambio",
        statusSmuTimeout: "Tiempo agotado en la SMU — inténtalo de nuevo",
        statusSmuBusy: "SMU ocupada — inténtalo de nuevo",
        statusOutOfRange: "Valor fuera del rango seguro",
        statusInvalidCore: "Índice de núcleo no válido",
        statusInvalidFrequency: "Petición de frecuencia no válida",
        statusInvalidOcMode: "Petición de modo OC no válida",
        statusEnableOcFirst: "Activa primero el modo OC (este driver debe abrir el acceso)",
        statusFailedCodeFormat: "Error (0x%08X)",
        coreLabelFormat: "Núcleo %d",
        coreOffsetAppliedFormat: "Núcleo %d → %d",
        coresAppliedFormat: "Núcleos escritos: %d",
        coLowerFormat: "Bajar el offset del núcleo %d",
        coRaiseFormat: "Subir el offset del núcleo %d",
        pmCaptureFailed: "No se pudo capturar la tabla PM",
        exportFailed: "No se pudo exportar",
        discardChangesTitle: "¿Descartar los cambios sin guardar de la curva?",
        discardChangesButton: "Descartar",
        deleteCurveInUseTitle: "¿Eliminar una curva en uso?",
        deleteCurveInUseMessage: "Los ventiladores que siguen esta curva vuelven al control de la BIOS.",
        curveRejectedHint: "La curva no se guardó: revisa sus puntos.",
        curvePointLabelFormat: "Punto de la curva %d",
        curvePointValueFormat: "%d °C, %d%% de ciclo",
        pwmFloorFormat: "Mínimo %d%%",
        unknownCurve: "Desconocida",
        intervalThreeSeconds: "3 segundos"
    )
}

extension DashboardFeatureStrings {
    static let de = DashboardFeatureStrings(
        totalUtilization: "Gesamtauslastung",
        temperatureShort: "Temp.",
        frequencyShort: "Takt",
        powerShort: "Leistung",
        memoryAndStorage: "Speicher & Laufwerke",
        diskIO: "Datenträger-E/A",
        diskReadWriteFormat: "L %@  S %@",
        networkTraffic: "Netzwerkverkehr",
        processManager: "Prozessverwaltung",
        sortBy: "Sortieren nach:",
        usageColumn: "Nutzung",
        processCountFormat: "Prozesse: %d",
        loadingProcesses: "Prozesse werden geladen…",
        noGPUProcesses: "Diese GPU meldet keine GPU-Zeit pro Prozess.",
        killShort: "Beenden",
        cpuTopologyFormat: "Kerne: %d · Threads: %d",
        memoryUsedPercentFormat: "%@ belegt",
        memoryTotalFormat: "%@ gesamt",
        vramTotalFormat: "%@ VRAM",
        hottestCoreFormat: "Heißester Kern %@",
        fabricClocksTitle: "Fabric (MHz)",
        coreParkedLegend: "— schlafend",
        pmVoltageHelp: "Spannung pro Kern (SMU)",
        pmC0Help: "C0-Verweildauer (%)",
        pmCC6Help: "CC6-Verweildauer (%)",
        gpuCompute: "GPU-Rechenlast",
        averageFormat: "Ø %@",
        chartSummaryFormat: "Durchschnitt %@, Spitze %@, zuletzt %@",
        ipAddressFormat: "IP: %@",
        categorySystem: "System",
        categoryApp: "App",
        categoryHelper: "Hilfsprozess",
        categoryBackground: "Hintergrund",
        categoryDeveloper: "Entwicklung",
        categorySecurity: "Sicherheit",
        statusRequiresRoot: "Erfordert root oder -amdpnopchk",
        statusNotSupported: "Auf dieser CPU vom Kext nicht unterstützt",
        statusNotReady: "Abgelehnt: Package über 75 °C oder Treiber nicht bereit",
        statusSmuRejected: "Die SMU hat die Änderung abgelehnt",
        statusSmuTimeout: "SMU-Zeitüberschreitung — erneut versuchen",
        statusSmuBusy: "SMU beschäftigt — erneut versuchen",
        statusOutOfRange: "Wert außerhalb des sicheren Bereichs",
        statusInvalidCore: "Ungültige Kernnummer",
        statusInvalidFrequency: "Ungültige Taktanforderung",
        statusInvalidOcMode: "Ungültige OC-Modus-Anforderung",
        statusEnableOcFirst: "Zuerst den OC-Modus aktivieren (dieser Treiber muss den Zugang selbst öffnen)",
        statusFailedCodeFormat: "Fehlgeschlagen (0x%08X)",
        coreLabelFormat: "Kern %d",
        coreOffsetAppliedFormat: "Kern %d → %d",
        coresAppliedFormat: "Geschriebene Kerne: %d",
        coLowerFormat: "Offset von Kern %d senken",
        coRaiseFormat: "Offset von Kern %d erhöhen",
        pmCaptureFailed: "PM-Tabelle konnte nicht erfasst werden",
        exportFailed: "Export fehlgeschlagen",
        discardChangesTitle: "Nicht gesicherte Kurvenänderungen verwerfen?",
        discardChangesButton: "Verwerfen",
        deleteCurveInUseTitle: "Eine verwendete Kurve löschen?",
        deleteCurveInUseMessage: "Lüfter, die dieser Kurve folgen, kehren zur BIOS-Steuerung zurück.",
        curveRejectedHint: "Die Kurve wurde nicht gespeichert: Punkte prüfen.",
        curvePointLabelFormat: "Kurvenpunkt %d",
        curvePointValueFormat: "%d °C, %d %% Tastgrad",
        pwmFloorFormat: "Minimum %d %%",
        unknownCurve: "Unbekannt",
        intervalThreeSeconds: "3 Sekunden"
    )
}

extension DashboardFeatureStrings {
    static let fr = DashboardFeatureStrings(
        totalUtilization: "Utilisation totale",
        temperatureShort: "Temp.",
        frequencyShort: "Fréq.",
        powerShort: "Puissance",
        memoryAndStorage: "Mémoire et stockage",
        diskIO: "E/S disque",
        diskReadWriteFormat: "L %@  É %@",
        networkTraffic: "Trafic réseau",
        processManager: "Gestionnaire de processus",
        sortBy: "Trier par :",
        usageColumn: "Utilisation",
        processCountFormat: "Processus : %d",
        loadingProcesses: "Chargement des processus…",
        noGPUProcesses: "Ce GPU ne fournit pas de temps GPU par processus.",
        killShort: "Arrêter",
        cpuTopologyFormat: "Cœurs : %d · Threads : %d",
        memoryUsedPercentFormat: "%@ utilisés",
        memoryTotalFormat: "%@ au total",
        vramTotalFormat: "%@ de VRAM",
        hottestCoreFormat: "Cœur le plus chaud %@",
        fabricClocksTitle: "Fabric (MHz)",
        coreParkedLegend: "— en veille",
        pmVoltageHelp: "Tension par cœur (SMU)",
        pmC0Help: "Résidence C0 (%)",
        pmCC6Help: "Résidence CC6 (%)",
        gpuCompute: "Calcul GPU",
        averageFormat: "Moy. %@",
        chartSummaryFormat: "Moyenne %@, pic %@, dernier %@",
        ipAddressFormat: "IP : %@",
        categorySystem: "Système",
        categoryApp: "App",
        categoryHelper: "Assistant",
        categoryBackground: "Arrière-plan",
        categoryDeveloper: "Développement",
        categorySecurity: "Sécurité",
        statusRequiresRoot: "Nécessite root ou -amdpnopchk",
        statusNotSupported: "Non pris en charge par le kext sur ce CPU",
        statusNotReady: "Refusé : boîtier au-dessus de 75 °C ou pilote pas prêt",
        statusSmuRejected: "Le SMU a refusé la modification",
        statusSmuTimeout: "Délai SMU dépassé — réessayez",
        statusSmuBusy: "SMU occupé — réessayez",
        statusOutOfRange: "Valeur hors de la plage sûre",
        statusInvalidCore: "Numéro de cœur non valide",
        statusInvalidFrequency: "Demande de fréquence non valide",
        statusInvalidOcMode: "Demande de mode OC non valide",
        statusEnableOcFirst: "Activez d'abord le mode OC (ce pilote doit ouvrir l'accès lui-même)",
        statusFailedCodeFormat: "Échec (0x%08X)",
        coreLabelFormat: "Cœur %d",
        coreOffsetAppliedFormat: "Cœur %d → %d",
        coresAppliedFormat: "Cœurs écrits : %d",
        coLowerFormat: "Baisser le décalage du cœur %d",
        coRaiseFormat: "Augmenter le décalage du cœur %d",
        pmCaptureFailed: "Capture de la table PM impossible",
        exportFailed: "Échec de l'export",
        discardChangesTitle: "Abandonner les modifications non enregistrées de la courbe ?",
        discardChangesButton: "Abandonner",
        deleteCurveInUseTitle: "Supprimer une courbe utilisée ?",
        deleteCurveInUseMessage: "Les ventilateurs qui suivent cette courbe reviennent au contrôle du BIOS.",
        curveRejectedHint: "La courbe n'a pas été enregistrée : vérifiez ses points.",
        curvePointLabelFormat: "Point de courbe %d",
        curvePointValueFormat: "%d °C, rapport cyclique %d %%",
        pwmFloorFormat: "Minimum %d %%",
        unknownCurve: "Inconnue",
        intervalThreeSeconds: "3 secondes"
    )
}

extension DashboardFeatureStrings {
    static let it = DashboardFeatureStrings(
        totalUtilization: "Utilizzo totale",
        temperatureShort: "Temp.",
        frequencyShort: "Freq.",
        powerShort: "Potenza",
        memoryAndStorage: "Memoria e archiviazione",
        diskIO: "I/O disco",
        diskReadWriteFormat: "L %@  S %@",
        networkTraffic: "Traffico di rete",
        processManager: "Gestione processi",
        sortBy: "Ordina per:",
        usageColumn: "Utilizzo",
        processCountFormat: "Processi: %d",
        loadingProcesses: "Caricamento processi…",
        noGPUProcesses: "Questa GPU non riporta il tempo GPU per processo.",
        killShort: "Termina",
        cpuTopologyFormat: "Core: %d · Thread: %d",
        memoryUsedPercentFormat: "%@ in uso",
        memoryTotalFormat: "%@ totali",
        vramTotalFormat: "%@ di VRAM",
        hottestCoreFormat: "Core più caldo %@",
        fabricClocksTitle: "Fabric (MHz)",
        coreParkedLegend: "— a riposo",
        pmVoltageHelp: "Tensione per core (SMU)",
        pmC0Help: "Residenza in C0 (%)",
        pmCC6Help: "Residenza in CC6 (%)",
        gpuCompute: "Calcolo GPU",
        averageFormat: "Media %@",
        chartSummaryFormat: "Media %@, picco %@, ultimo %@",
        ipAddressFormat: "IP: %@",
        categorySystem: "Sistema",
        categoryApp: "App",
        categoryHelper: "Ausiliario",
        categoryBackground: "In background",
        categoryDeveloper: "Sviluppo",
        categorySecurity: "Sicurezza",
        statusRequiresRoot: "Richiede root o -amdpnopchk",
        statusNotSupported: "Non supportato dal kext su questa CPU",
        statusNotReady: "Rifiutato: package oltre 75 °C o driver non pronto",
        statusSmuRejected: "La SMU ha rifiutato la modifica",
        statusSmuTimeout: "Timeout della SMU — riprova",
        statusSmuBusy: "SMU occupata — riprova",
        statusOutOfRange: "Valore fuori dall'intervallo sicuro",
        statusInvalidCore: "Indice del core non valido",
        statusInvalidFrequency: "Richiesta di frequenza non valida",
        statusInvalidOcMode: "Richiesta di modalità OC non valida",
        statusEnableOcFirst: "Attiva prima la modalità OC (questo driver deve aprire l'accesso da sé)",
        statusFailedCodeFormat: "Non riuscito (0x%08X)",
        coreLabelFormat: "Core %d",
        coreOffsetAppliedFormat: "Core %d → %d",
        coresAppliedFormat: "Core scritti: %d",
        coLowerFormat: "Riduci l'offset del core %d",
        coRaiseFormat: "Aumenta l'offset del core %d",
        pmCaptureFailed: "Impossibile acquisire la tabella PM",
        exportFailed: "Esportazione non riuscita",
        discardChangesTitle: "Scartare le modifiche non salvate della curva?",
        discardChangesButton: "Scarta",
        deleteCurveInUseTitle: "Eliminare una curva in uso?",
        deleteCurveInUseMessage: "Le ventole che seguono questa curva tornano al controllo del BIOS.",
        curveRejectedHint: "La curva non è stata salvata: controlla i punti.",
        curvePointLabelFormat: "Punto della curva %d",
        curvePointValueFormat: "%d °C, duty %d%%",
        pwmFloorFormat: "Minimo %d%%",
        unknownCurve: "Sconosciuta",
        intervalThreeSeconds: "3 secondi"
    )
}

extension DashboardFeatureStrings {
    static let ja = DashboardFeatureStrings(
        totalUtilization: "全体の使用率",
        temperatureShort: "温度",
        frequencyShort: "周波数",
        powerShort: "電力",
        memoryAndStorage: "メモリとストレージ",
        diskIO: "ディスク I/O",
        diskReadWriteFormat: "読み %@  書き %@",
        networkTraffic: "ネットワーク通信",
        processManager: "プロセスマネージャ",
        sortBy: "並べ替え:",
        usageColumn: "使用量",
        processCountFormat: "プロセス: %d",
        loadingProcesses: "プロセスを読み込み中…",
        noGPUProcesses: "このGPUはプロセスごとのGPU時間を報告しません。",
        killShort: "終了",
        cpuTopologyFormat: "コア: %d · スレッド: %d",
        memoryUsedPercentFormat: "%@ 使用中",
        memoryTotalFormat: "合計 %@",
        vramTotalFormat: "VRAM %@",
        hottestCoreFormat: "最高温コア %@",
        fabricClocksTitle: "Fabric (MHz)",
        coreParkedLegend: "— 休止中",
        pmVoltageHelp: "コアごとの電圧 (SMU)",
        pmC0Help: "C0 滞在率 (%)",
        pmCC6Help: "CC6 滞在率 (%)",
        gpuCompute: "GPU 演算",
        averageFormat: "平均 %@",
        chartSummaryFormat: "平均 %@、最大 %@、最新 %@",
        ipAddressFormat: "IP: %@",
        categorySystem: "システム",
        categoryApp: "アプリ",
        categoryHelper: "ヘルパー",
        categoryBackground: "バックグラウンド",
        categoryDeveloper: "開発",
        categorySecurity: "セキュリティ",
        statusRequiresRoot: "root または -amdpnopchk が必要です",
        statusNotSupported: "このCPUではkextが対応していません",
        statusNotReady: "拒否: パッケージが75 °C超、またはドライバの準備ができていません",
        statusSmuRejected: "SMUが変更を拒否しました",
        statusSmuTimeout: "SMUがタイムアウト — もう一度お試しください",
        statusSmuBusy: "SMUがビジー — もう一度お試しください",
        statusOutOfRange: "値が安全範囲外です",
        statusInvalidCore: "無効なコア番号",
        statusInvalidFrequency: "無効な周波数要求",
        statusInvalidOcMode: "無効なOCモード要求",
        statusEnableOcFirst: "先にOCモードを有効にしてください(このドライバ自身がゲートを開く必要があります)",
        statusFailedCodeFormat: "失敗 (0x%08X)",
        coreLabelFormat: "コア %d",
        coreOffsetAppliedFormat: "コア %d → %d",
        coresAppliedFormat: "書き込んだコア: %d",
        coLowerFormat: "コア %d のオフセットを下げる",
        coRaiseFormat: "コア %d のオフセットを上げる",
        pmCaptureFailed: "PMテーブルを取得できませんでした",
        exportFailed: "書き出しに失敗しました",
        discardChangesTitle: "保存していないカーブの変更を破棄しますか?",
        discardChangesButton: "破棄",
        deleteCurveInUseTitle: "使用中のカーブを削除しますか?",
        deleteCurveInUseMessage: "このカーブに従うファンはBIOS制御に戻ります。",
        curveRejectedHint: "カーブは保存されませんでした。ポイントを確認してください。",
        curvePointLabelFormat: "カーブポイント %d",
        curvePointValueFormat: "%d °C、デューティ %d%%",
        pwmFloorFormat: "最低 %d%%",
        unknownCurve: "不明",
        intervalThreeSeconds: "3秒"
    )
}

extension DashboardFeatureStrings {
    static let ko = DashboardFeatureStrings(
        totalUtilization: "전체 사용률",
        temperatureShort: "온도",
        frequencyShort: "클럭",
        powerShort: "전력",
        memoryAndStorage: "메모리 및 저장 장치",
        diskIO: "디스크 I/O",
        diskReadWriteFormat: "읽기 %@  쓰기 %@",
        networkTraffic: "네트워크 트래픽",
        processManager: "프로세스 관리자",
        sortBy: "정렬 기준:",
        usageColumn: "사용량",
        processCountFormat: "프로세스: %d",
        loadingProcesses: "프로세스 불러오는 중…",
        noGPUProcesses: "이 GPU는 프로세스별 GPU 시간을 보고하지 않습니다.",
        killShort: "종료",
        cpuTopologyFormat: "코어: %d · 스레드: %d",
        memoryUsedPercentFormat: "%@ 사용 중",
        memoryTotalFormat: "총 %@",
        vramTotalFormat: "VRAM %@",
        hottestCoreFormat: "가장 뜨거운 코어 %@",
        fabricClocksTitle: "Fabric (MHz)",
        coreParkedLegend: "— 휴면",
        pmVoltageHelp: "코어별 전압 (SMU)",
        pmC0Help: "C0 체류율 (%)",
        pmCC6Help: "CC6 체류율 (%)",
        gpuCompute: "GPU 연산",
        averageFormat: "평균 %@",
        chartSummaryFormat: "평균 %@, 최고 %@, 최근 %@",
        ipAddressFormat: "IP: %@",
        categorySystem: "시스템",
        categoryApp: "앱",
        categoryHelper: "도우미",
        categoryBackground: "백그라운드",
        categoryDeveloper: "개발",
        categorySecurity: "보안",
        statusRequiresRoot: "root 또는 -amdpnopchk가 필요합니다",
        statusNotSupported: "이 CPU에서는 kext가 지원하지 않습니다",
        statusNotReady: "거부됨: 패키지가 75 °C 이상이거나 드라이버가 준비되지 않음",
        statusSmuRejected: "SMU가 변경을 거부했습니다",
        statusSmuTimeout: "SMU 시간 초과 — 다시 시도하세요",
        statusSmuBusy: "SMU 사용 중 — 다시 시도하세요",
        statusOutOfRange: "안전 범위를 벗어난 값",
        statusInvalidCore: "잘못된 코어 번호",
        statusInvalidFrequency: "잘못된 클럭 요청",
        statusInvalidOcMode: "잘못된 OC 모드 요청",
        statusEnableOcFirst: "먼저 OC 모드를 켜세요 (이 드라이버가 직접 게이트를 열어야 합니다)",
        statusFailedCodeFormat: "실패 (0x%08X)",
        coreLabelFormat: "코어 %d",
        coreOffsetAppliedFormat: "코어 %d → %d",
        coresAppliedFormat: "기록한 코어: %d",
        coLowerFormat: "코어 %d 오프셋 낮추기",
        coRaiseFormat: "코어 %d 오프셋 높이기",
        pmCaptureFailed: "PM 테이블을 가져오지 못했습니다",
        exportFailed: "내보내기 실패",
        discardChangesTitle: "저장하지 않은 커브 변경 사항을 버릴까요?",
        discardChangesButton: "버리기",
        deleteCurveInUseTitle: "사용 중인 커브를 삭제할까요?",
        deleteCurveInUseMessage: "이 커브를 따르는 팬은 BIOS 제어로 돌아갑니다.",
        curveRejectedHint: "커브가 저장되지 않았습니다. 포인트를 확인하세요.",
        curvePointLabelFormat: "커브 포인트 %d",
        curvePointValueFormat: "%d °C, 듀티 %d%%",
        pwmFloorFormat: "최소 %d%%",
        unknownCurve: "알 수 없음",
        intervalThreeSeconds: "3초"
    )
}

extension DashboardFeatureStrings {
    static let zhHans = DashboardFeatureStrings(
        totalUtilization: "总使用率",
        temperatureShort: "温度",
        frequencyShort: "频率",
        powerShort: "功耗",
        memoryAndStorage: "内存与存储",
        diskIO: "磁盘 I/O",
        diskReadWriteFormat: "读 %@  写 %@",
        networkTraffic: "网络流量",
        processManager: "进程管理器",
        sortBy: "排序方式:",
        usageColumn: "占用",
        processCountFormat: "进程:%d",
        loadingProcesses: "正在载入进程…",
        noGPUProcesses: "此 GPU 不报告按进程统计的 GPU 时间。",
        killShort: "结束",
        cpuTopologyFormat: "核心:%d · 线程:%d",
        memoryUsedPercentFormat: "已用 %@",
        memoryTotalFormat: "共 %@",
        vramTotalFormat: "VRAM %@",
        hottestCoreFormat: "最热核心 %@",
        fabricClocksTitle: "Fabric (MHz)",
        coreParkedLegend: "— 休眠",
        pmVoltageHelp: "每核心电压 (SMU)",
        pmC0Help: "C0 驻留率 (%)",
        pmCC6Help: "CC6 驻留率 (%)",
        gpuCompute: "GPU 计算",
        averageFormat: "平均 %@",
        chartSummaryFormat: "平均 %@,峰值 %@,最新 %@",
        ipAddressFormat: "IP:%@",
        categorySystem: "系统",
        categoryApp: "应用",
        categoryHelper: "辅助进程",
        categoryBackground: "后台",
        categoryDeveloper: "开发",
        categorySecurity: "安全",
        statusRequiresRoot: "需要 root 或 -amdpnopchk",
        statusNotSupported: "此 CPU 上 kext 不支持",
        statusNotReady: "已拒绝:封装温度高于 75 °C,或驱动尚未就绪",
        statusSmuRejected: "SMU 拒绝了此更改",
        statusSmuTimeout: "SMU 超时 — 请重试",
        statusSmuBusy: "SMU 繁忙 — 请重试",
        statusOutOfRange: "数值超出安全范围",
        statusInvalidCore: "无效的核心编号",
        statusInvalidFrequency: "无效的频率请求",
        statusInvalidOcMode: "无效的 OC 模式请求",
        statusEnableOcFirst: "请先启用 OC 模式(必须由此驱动自行打开)",
        statusFailedCodeFormat: "失败 (0x%08X)",
        coreLabelFormat: "核心 %d",
        coreOffsetAppliedFormat: "核心 %d → %d",
        coresAppliedFormat: "已写入核心:%d",
        coLowerFormat: "降低核心 %d 偏移",
        coRaiseFormat: "提高核心 %d 偏移",
        pmCaptureFailed: "PM 表采集失败",
        exportFailed: "导出失败",
        discardChangesTitle: "放弃未保存的曲线更改?",
        discardChangesButton: "放弃",
        deleteCurveInUseTitle: "删除正在使用的曲线?",
        deleteCurveInUseMessage: "跟随此曲线的风扇将回到 BIOS 控制。",
        curveRejectedHint: "曲线未保存:请检查其控制点。",
        curvePointLabelFormat: "曲线点 %d",
        curvePointValueFormat: "%d °C,占空比 %d%%",
        pwmFloorFormat: "最低 %d%%",
        unknownCurve: "未知",
        intervalThreeSeconds: "3 秒"
    )
}

extension DashboardFeatureStrings {
    static let zhTW = DashboardFeatureStrings(
        totalUtilization: "總使用率",
        temperatureShort: "溫度",
        frequencyShort: "頻率",
        powerShort: "功耗",
        memoryAndStorage: "記憶體與儲存",
        diskIO: "磁碟 I/O",
        diskReadWriteFormat: "讀 %@  寫 %@",
        networkTraffic: "網路流量",
        processManager: "程序管理員",
        sortBy: "排序方式:",
        usageColumn: "佔用",
        processCountFormat: "程序:%d",
        loadingProcesses: "正在載入程序…",
        noGPUProcesses: "此 GPU 不回報各程序的 GPU 時間。",
        killShort: "結束",
        cpuTopologyFormat: "核心:%d · 執行緒:%d",
        memoryUsedPercentFormat: "已用 %@",
        memoryTotalFormat: "共 %@",
        vramTotalFormat: "VRAM %@",
        hottestCoreFormat: "最熱核心 %@",
        fabricClocksTitle: "Fabric (MHz)",
        coreParkedLegend: "— 休眠",
        pmVoltageHelp: "各核心電壓 (SMU)",
        pmC0Help: "C0 駐留率 (%)",
        pmCC6Help: "CC6 駐留率 (%)",
        gpuCompute: "GPU 運算",
        averageFormat: "平均 %@",
        chartSummaryFormat: "平均 %@,峰值 %@,最新 %@",
        ipAddressFormat: "IP:%@",
        categorySystem: "系統",
        categoryApp: "App",
        categoryHelper: "輔助程序",
        categoryBackground: "背景",
        categoryDeveloper: "開發",
        categorySecurity: "安全性",
        statusRequiresRoot: "需要 root 或 -amdpnopchk",
        statusNotSupported: "此 CPU 上 kext 不支援",
        statusNotReady: "已拒絕:封裝溫度高於 75 °C,或驅動程式尚未就緒",
        statusSmuRejected: "SMU 拒絕了此變更",
        statusSmuTimeout: "SMU 逾時 — 請再試一次",
        statusSmuBusy: "SMU 忙碌 — 請再試一次",
        statusOutOfRange: "數值超出安全範圍",
        statusInvalidCore: "無效的核心編號",
        statusInvalidFrequency: "無效的頻率要求",
        statusInvalidOcMode: "無效的 OC 模式要求",
        statusEnableOcFirst: "請先啟用 OC 模式(必須由此驅動程式自行開啟)",
        statusFailedCodeFormat: "失敗 (0x%08X)",
        coreLabelFormat: "核心 %d",
        coreOffsetAppliedFormat: "核心 %d → %d",
        coresAppliedFormat: "已寫入核心:%d",
        coLowerFormat: "降低核心 %d 偏移",
        coRaiseFormat: "提高核心 %d 偏移",
        pmCaptureFailed: "PM 表擷取失敗",
        exportFailed: "匯出失敗",
        discardChangesTitle: "要捨棄未儲存的曲線變更嗎?",
        discardChangesButton: "捨棄",
        deleteCurveInUseTitle: "要刪除使用中的曲線嗎?",
        deleteCurveInUseMessage: "跟隨此曲線的風扇會回到 BIOS 控制。",
        curveRejectedHint: "曲線未儲存:請檢查其控制點。",
        curvePointLabelFormat: "曲線點 %d",
        curvePointValueFormat: "%d °C,工作週期 %d%%",
        pwmFloorFormat: "最低 %d%%",
        unknownCurve: "未知",
        intervalThreeSeconds: "3 秒"
    )
}

extension DashboardFeatureStrings {
    static let zhHK = DashboardFeatureStrings(
        totalUtilization: "總使用率",
        temperatureShort: "溫度",
        frequencyShort: "頻率",
        powerShort: "功耗",
        memoryAndStorage: "記憶體與儲存",
        diskIO: "磁碟 I/O",
        diskReadWriteFormat: "讀 %@  寫 %@",
        networkTraffic: "網絡流量",
        processManager: "程序管理器",
        sortBy: "排序方式:",
        usageColumn: "佔用",
        processCountFormat: "程序:%d",
        loadingProcesses: "正在載入程序…",
        noGPUProcesses: "此 GPU 不會報告各程序的 GPU 時間。",
        killShort: "結束",
        cpuTopologyFormat: "核心:%d · 線程:%d",
        memoryUsedPercentFormat: "已用 %@",
        memoryTotalFormat: "共 %@",
        vramTotalFormat: "VRAM %@",
        hottestCoreFormat: "最熱核心 %@",
        fabricClocksTitle: "Fabric (MHz)",
        coreParkedLegend: "— 休眠",
        pmVoltageHelp: "各核心電壓 (SMU)",
        pmC0Help: "C0 駐留率 (%)",
        pmCC6Help: "CC6 駐留率 (%)",
        gpuCompute: "GPU 運算",
        averageFormat: "平均 %@",
        chartSummaryFormat: "平均 %@,峰值 %@,最新 %@",
        ipAddressFormat: "IP:%@",
        categorySystem: "系統",
        categoryApp: "App",
        categoryHelper: "輔助程序",
        categoryBackground: "背景",
        categoryDeveloper: "開發",
        categorySecurity: "保安",
        statusRequiresRoot: "需要 root 或 -amdpnopchk",
        statusNotSupported: "此 CPU 上 kext 不支援",
        statusNotReady: "已拒絕:封裝溫度高於 75 °C,或驅動程式尚未就緒",
        statusSmuRejected: "SMU 拒絕了此變更",
        statusSmuTimeout: "SMU 逾時 — 請再試",
        statusSmuBusy: "SMU 忙碌 — 請再試",
        statusOutOfRange: "數值超出安全範圍",
        statusInvalidCore: "無效的核心編號",
        statusInvalidFrequency: "無效的頻率要求",
        statusInvalidOcMode: "無效的 OC 模式要求",
        statusEnableOcFirst: "請先啟用 OC 模式(必須由此驅動程式自行開啟)",
        statusFailedCodeFormat: "失敗 (0x%08X)",
        coreLabelFormat: "核心 %d",
        coreOffsetAppliedFormat: "核心 %d → %d",
        coresAppliedFormat: "已寫入核心:%d",
        coLowerFormat: "降低核心 %d 偏移",
        coRaiseFormat: "提高核心 %d 偏移",
        pmCaptureFailed: "PM 表擷取失敗",
        exportFailed: "匯出失敗",
        discardChangesTitle: "要捨棄未儲存的曲線變更嗎?",
        discardChangesButton: "捨棄",
        deleteCurveInUseTitle: "要刪除使用中的曲線嗎?",
        deleteCurveInUseMessage: "跟隨此曲線的風扇會回到 BIOS 控制。",
        curveRejectedHint: "曲線未儲存:請檢查其控制點。",
        curvePointLabelFormat: "曲線點 %d",
        curvePointValueFormat: "%d °C,工作週期 %d%%",
        pwmFloorFormat: "最低 %d%%",
        unknownCurve: "未知",
        intervalThreeSeconds: "3 秒"
    )
}

extension DashboardFeatureStrings {
    static let sk = DashboardFeatureStrings(
        totalUtilization: "Celkové vyťaženie",
        temperatureShort: "Tepl.",
        frequencyShort: "Frekv.",
        powerShort: "Príkon",
        memoryAndStorage: "Pamäť a úložisko",
        diskIO: "V/V disku",
        diskReadWriteFormat: "Č %@  Z %@",
        networkTraffic: "Sieťová prevádzka",
        processManager: "Správca procesov",
        sortBy: "Zoradiť podľa:",
        usageColumn: "Využitie",
        processCountFormat: "Procesy: %d",
        loadingProcesses: "Načítavajú sa procesy…",
        noGPUProcesses: "Toto GPU nehlási čas GPU po procesoch.",
        killShort: "Ukončiť",
        cpuTopologyFormat: "Jadrá: %d · Vlákna: %d",
        memoryUsedPercentFormat: "Využité: %@",
        memoryTotalFormat: "Celkom: %@",
        vramTotalFormat: "VRAM: %@",
        hottestCoreFormat: "Najteplejšie jadro %@",
        fabricClocksTitle: "Fabric (MHz)",
        coreParkedLegend: "— v nečinnosti",
        pmVoltageHelp: "Napätie po jadrách (SMU)",
        pmC0Help: "Podiel v C0 (%)",
        pmCC6Help: "Podiel v CC6 (%)",
        gpuCompute: "Výpočty GPU",
        averageFormat: "Priem. %@",
        chartSummaryFormat: "Priemer %@, maximum %@, posledné %@",
        ipAddressFormat: "IP: %@",
        categorySystem: "Systém",
        categoryApp: "Aplikácia",
        categoryHelper: "Pomocník",
        categoryBackground: "Na pozadí",
        categoryDeveloper: "Vývoj",
        categorySecurity: "Zabezpečenie",
        statusRequiresRoot: "Vyžaduje root alebo -amdpnopchk",
        statusNotSupported: "Kext to na tomto CPU nepodporuje",
        statusNotReady: "Odmietnuté: puzdro nad 75 °C alebo ovládač nie je pripravený",
        statusSmuRejected: "SMU zmenu odmietla",
        statusSmuTimeout: "Časový limit SMU — skúste znova",
        statusSmuBusy: "SMU je zaneprázdnená — skúste znova",
        statusOutOfRange: "Hodnota mimo bezpečného rozsahu",
        statusInvalidCore: "Neplatné číslo jadra",
        statusInvalidFrequency: "Neplatná požiadavka na frekvenciu",
        statusInvalidOcMode: "Neplatná požiadavka na režim OC",
        statusEnableOcFirst: "Najprv zapnite režim OC (tento ovládač musí prístup otvoriť sám)",
        statusFailedCodeFormat: "Zlyhalo (0x%08X)",
        coreLabelFormat: "Jadro %d",
        coreOffsetAppliedFormat: "Jadro %d → %d",
        coresAppliedFormat: "Zapísané jadrá: %d",
        coLowerFormat: "Znížiť posun jadra %d",
        coRaiseFormat: "Zvýšiť posun jadra %d",
        pmCaptureFailed: "Tabuľku PM sa nepodarilo zachytiť",
        exportFailed: "Export zlyhal",
        discardChangesTitle: "Zahodiť neuložené zmeny krivky?",
        discardChangesButton: "Zahodiť",
        deleteCurveInUseTitle: "Vymazať používanú krivku?",
        deleteCurveInUseMessage: "Ventilátory, ktoré sa riadia touto krivkou, sa vrátia pod riadenie BIOS.",
        curveRejectedHint: "Krivka sa neuložila: skontrolujte jej body.",
        curvePointLabelFormat: "Bod krivky %d",
        curvePointValueFormat: "%d °C, strieda %d %%",
        pwmFloorFormat: "Minimum %d %%",
        unknownCurve: "Neznáma",
        intervalThreeSeconds: "3 sekundy"
    )
}

extension DashboardFeatureStrings {
    static let uk = DashboardFeatureStrings(
        totalUtilization: "Загальне навантаження",
        temperatureShort: "Темп.",
        frequencyShort: "Частота",
        powerShort: "Потужність",
        memoryAndStorage: "Пам'ять і накопичувачі",
        diskIO: "Диск: ввід-вивід",
        diskReadWriteFormat: "Чит %@  Зап %@",
        networkTraffic: "Мережевий трафік",
        processManager: "Диспетчер процесів",
        sortBy: "Сортування:",
        usageColumn: "Навантаження",
        processCountFormat: "Процесів: %d",
        loadingProcesses: "Завантаження процесів…",
        noGPUProcesses: "Цей GPU не повідомляє час GPU за процесами.",
        killShort: "Завершити",
        cpuTopologyFormat: "Ядер: %d · Потоків: %d",
        memoryUsedPercentFormat: "Зайнято %@",
        memoryTotalFormat: "Усього %@",
        vramTotalFormat: "VRAM %@",
        hottestCoreFormat: "Найгарячіше ядро %@",
        fabricClocksTitle: "Fabric (МГц)",
        coreParkedLegend: "— у простої",
        pmVoltageHelp: "Напруга за ядрами (SMU)",
        pmC0Help: "Частка в C0 (%)",
        pmCC6Help: "Частка в CC6 (%)",
        gpuCompute: "Обчислення GPU",
        averageFormat: "Сер. %@",
        chartSummaryFormat: "Середнє %@, пік %@, останнє %@",
        ipAddressFormat: "IP: %@",
        categorySystem: "Система",
        categoryApp: "Застосунок",
        categoryHelper: "Помічник",
        categoryBackground: "Фоновий",
        categoryDeveloper: "Розробка",
        categorySecurity: "Безпека",
        statusRequiresRoot: "Потрібні права root або -amdpnopchk",
        statusNotSupported: "Kext не підтримує це на цьому CPU",
        statusNotReady: "Відмовлено: корпус вище 75 °C або драйвер не готовий",
        statusSmuRejected: "SMU відхилив зміну",
        statusSmuTimeout: "Тайм-аут SMU — спробуйте ще раз",
        statusSmuBusy: "SMU зайнятий — спробуйте ще раз",
        statusOutOfRange: "Значення поза безпечним діапазоном",
        statusInvalidCore: "Неправильний номер ядра",
        statusInvalidFrequency: "Неправильний запит частоти",
        statusInvalidOcMode: "Неправильний запит режиму OC",
        statusEnableOcFirst: "Спершу ввімкніть режим OC (драйвер має сам відкрити доступ)",
        statusFailedCodeFormat: "Помилка (0x%08X)",
        coreLabelFormat: "Ядро %d",
        coreOffsetAppliedFormat: "Ядро %d → %d",
        coresAppliedFormat: "Записано ядер: %d",
        coLowerFormat: "Зменшити зсув ядра %d",
        coRaiseFormat: "Збільшити зсув ядра %d",
        pmCaptureFailed: "Не вдалося зняти таблицю PM",
        exportFailed: "Не вдалося експортувати",
        discardChangesTitle: "Скасувати незбережені зміни кривої?",
        discardChangesButton: "Скасувати зміни",
        deleteCurveInUseTitle: "Видалити криву, що використовується?",
        deleteCurveInUseMessage: "Вентилятори, що працюють за цією кривою, повернуться під керування BIOS.",
        curveRejectedHint: "Криву не збережено: перевірте її точки.",
        curvePointLabelFormat: "Точка кривої %d",
        curvePointValueFormat: "%d °C, шпаруватість %d%%",
        pwmFloorFormat: "Мінімум %d%%",
        unknownCurve: "Невідомо",
        intervalThreeSeconds: "3 секунди"
    )
}
