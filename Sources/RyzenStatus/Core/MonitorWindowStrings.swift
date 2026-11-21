// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

/// Text of the Monitor window: its title, the section names in the toolbar
/// and the View menu, and the labels the sections add.
struct MonitorWindowStrings {
    let windowTitle: String
    let summary: String
    let processes: String
    let processor: String
    let network: String
    let history: String
    let diagnostics: String
    /// The accessibility name of the section control.
    let section: String
    let cores: String
    /// Active cores out of the cores present, e.g. "9 of 12 active".
    let activeCoresFormat: String
    let pptLimitFormat: String
    let voltage: String
    let openMonitor: String
    let openMonitorCaption: String
    let interfaceColumn: String
    let addressColumn: String
    let statusColumn: String
    let statusUp: String
    let statusDown: String
    /// The accessibility name of the History metric menu.
    let metric: String
    let cpuTemperature: String
    let gpuTemperature: String
    let systemPower: String
    /// The History chart's headline, e.g. "Average 12 %, peak 64 %".
    let averagePeakFormat: String
    let noHistory: String
    let severityCritical: String
    let severityWarning: String
    let severityInfo: String
    /// The View menu's title, as macOS names it in each language.
    let viewMenu: String
    let gpuColumn: String
    /// The time axis's name for VoiceOver in the History chart.
    let chartTime: String
    /// Said when Terminate cannot act on the selected row any more.
    let killUnavailable: String
    /// Three %@: user, system and total CPU load, above the process table.
    let cpuLoadFormat: String
    let ok: String
    /// Said when Inspect finds the row's app gone or its pid reused.
    let processGone: String
    // Feature Hub names and descriptions of the four monitor extras.
    let hubDiagnosticsDescription: String
    let hubHistoryDescription: String
    let hubEnergyTitle: String
    let hubEnergyDescription: String
    let hubNetworkTitle: String
    let hubNetworkDescription: String

    static func localized(_ language: AppLanguage) -> Self {
        switch language {
        case .enUS:
            return Self(windowTitle: "RyzenStatus Monitor", summary: "Overview", processes: "Processes",
                        processor: "Processor", network: "Network", history: "History", diagnostics: "Diagnostics",
                        section: "Section", cores: "Cores", activeCoresFormat: "%d of %d active",
                        pptLimitFormat: "PPT limit: %@", voltage: "Voltage", openMonitor: "Open Monitor",
                        openMonitorCaption: "The Dashboard opens in its own window.",
                        interfaceColumn: "Interface", addressColumn: "Address", statusColumn: "Status",
                        statusUp: "Active", statusDown: "Inactive", metric: "Metric",
                        cpuTemperature: "CPU Temperature", gpuTemperature: "GPU Temperature",
                        systemPower: "System Power", averagePeakFormat: "Average %@, peak %@",
                        noHistory: "No data for this period",
                        severityCritical: "Critical", severityWarning: "Warning", severityInfo: "Information", viewMenu: "View",
                        gpuColumn: "GPU %", chartTime: "Time",
                        killUnavailable: "This app can’t be terminated now. It may have quit or restarted.",
                        cpuLoadFormat: "CPU — User %@ · System %@ · Total %@", ok: "OK",
                        processGone: "This app is no longer running, or its process now belongs to another app.",
                        hubDiagnosticsDescription: "Notices for memory leaks, runaway processes, memory pressure and a hot CPU.",
                        hubHistoryDescription: "Charts of CPU, GPU, memory, network, disk, temperatures and power over up to 30 days.",
                        hubEnergyTitle: "Energy Impact", hubEnergyDescription: "Estimated energy impact of each app, from its CPU and GPU share.",
                        hubNetworkTitle: "Network Details", hubNetworkDescription: "Every network adapter with its address, state and live traffic.")
        case .ptBR:
            return Self(windowTitle: "Monitor do RyzenStatus", summary: "Visão geral", processes: "Processos",
                        processor: "Processador", network: "Rede", history: "Histórico", diagnostics: "Diagnóstico",
                        section: "Seção", cores: "Núcleos", activeCoresFormat: "%d de %d ativos",
                        pptLimitFormat: "Limite PPT: %@", voltage: "Tensão", openMonitor: "Abrir Monitor",
                        openMonitorCaption: "O Painel abre em uma janela própria.",
                        interfaceColumn: "Interface", addressColumn: "Endereço", statusColumn: "Estado",
                        statusUp: "Ativa", statusDown: "Inativa", metric: "Métrica",
                        cpuTemperature: "Temperatura da CPU", gpuTemperature: "Temperatura da GPU",
                        systemPower: "Consumo do sistema", averagePeakFormat: "Média %@, pico %@",
                        noHistory: "Sem dados para este período",
                        severityCritical: "Crítico", severityWarning: "Aviso", severityInfo: "Informação", viewMenu: "Visualizar",
                        gpuColumn: "GPU %", chartTime: "Hora",
                        killUnavailable: "Este app não pode ser encerrado agora. Ele pode ter sido fechado ou reiniciado.",
                        cpuLoadFormat: "CPU — Usuário %@ · Sistema %@ · Total %@", ok: "OK",
                        processGone: "Este app não está mais em execução, ou o processo agora pertence a outro app.",
                        hubDiagnosticsDescription: "Avisos de vazamentos de memória, processos descontrolados, pressão de memória e CPU quente.",
                        hubHistoryDescription: "Gráficos de CPU, GPU, memória, rede, disco, temperaturas e consumo de até 30 dias.",
                        hubEnergyTitle: "Impacto energético", hubEnergyDescription: "Impacto energético estimado de cada app, pela sua parcela de CPU e GPU.",
                        hubNetworkTitle: "Detalhes da rede", hubNetworkDescription: "Cada adaptador de rede com seu endereço, estado e tráfego ao vivo.")
        case .tr:
            return Self(windowTitle: "RyzenStatus İzleyici", summary: "Genel Bakış", processes: "İşlemler",
                        processor: "İşlemci", network: "Ağ", history: "Geçmiş", diagnostics: "Tanılama",
                        section: "Bölüm", cores: "Çekirdekler", activeCoresFormat: "%d / %d etkin",
                        pptLimitFormat: "PPT sınırı: %@", voltage: "Voltaj", openMonitor: "İzleyiciyi Aç",
                        openMonitorCaption: "Pano kendi penceresinde açılır.",
                        interfaceColumn: "Arabirim", addressColumn: "Adres", statusColumn: "Durum",
                        statusUp: "Etkin", statusDown: "Devre dışı", metric: "Ölçüm",
                        cpuTemperature: "CPU Sıcaklığı", gpuTemperature: "GPU Sıcaklığı",
                        systemPower: "Sistem Gücü", averagePeakFormat: "Ortalama %@, en yüksek %@",
                        noHistory: "Bu dönem için veri yok",
                        severityCritical: "Kritik", severityWarning: "Uyarı", severityInfo: "Bilgi", viewMenu: "Görüntü",
                        gpuColumn: "GPU %", chartTime: "Saat",
                        killUnavailable: "Bu uygulama şu anda sonlandırılamıyor. Kapanmış veya yeniden başlamış olabilir.",
                        cpuLoadFormat: "CPU — Kullanıcı %@ · Sistem %@ · Toplam %@", ok: "Tamam",
                        processGone: "Bu uygulama artık çalışmıyor ya da işlemi artık başka bir uygulamaya ait.",
                        hubDiagnosticsDescription: "Bellek sızıntıları, kontrolden çıkan işlemler, bellek baskısı ve sıcak CPU için uyarılar.",
                        hubHistoryDescription: "En fazla 30 günlük CPU, GPU, bellek, ağ, disk, sıcaklık ve güç grafikleri.",
                        hubEnergyTitle: "Enerji Etkisi", hubEnergyDescription: "Her uygulamanın CPU ve GPU payından tahmini enerji etkisi.",
                        hubNetworkTitle: "Ağ Ayrıntıları", hubNetworkDescription: "Her ağ bağdaştırıcısı; adresi, durumu ve canlı trafiğiyle.")
        case .ru:
            return Self(windowTitle: "Монитор RyzenStatus", summary: "Обзор", processes: "Процессы",
                        processor: "Процессор", network: "Сеть", history: "История", diagnostics: "Диагностика",
                        section: "Раздел", cores: "Ядра", activeCoresFormat: "активны: %d из %d",
                        pptLimitFormat: "Лимит PPT: %@", voltage: "Напряжение", openMonitor: "Открыть монитор",
                        openMonitorCaption: "Панель открывается в отдельном окне.",
                        interfaceColumn: "Интерфейс", addressColumn: "Адрес", statusColumn: "Состояние",
                        statusUp: "Активен", statusDown: "Неактивен", metric: "Показатель",
                        cpuTemperature: "Температура ЦП", gpuTemperature: "Температура ГП",
                        systemPower: "Мощность системы", averagePeakFormat: "Среднее %@, пик %@",
                        noHistory: "Нет данных за этот период",
                        severityCritical: "Критично", severityWarning: "Предупреждение", severityInfo: "Информация", viewMenu: "Вид",
                        gpuColumn: "GPU %", chartTime: "Время",
                        killUnavailable: "Это приложение сейчас нельзя завершить. Возможно, оно закрылось или перезапустилось.",
                        cpuLoadFormat: "ЦП — пользователь %@ · система %@ · всего %@", ok: "ОК",
                        processGone: "Это приложение больше не работает, или его процесс теперь принадлежит другому приложению.",
                        hubDiagnosticsDescription: "Предупреждения об утечках памяти, зависших процессах, нехватке памяти и перегреве ЦП.",
                        hubHistoryDescription: "Графики ЦП, ГП, памяти, сети, диска, температур и мощности за период до 30 дней.",
                        hubEnergyTitle: "Энергопотребление", hubEnergyDescription: "Оценка энергопотребления каждого приложения по его доле ЦП и ГП.",
                        hubNetworkTitle: "Сведения о сети", hubNetworkDescription: "Каждый сетевой адаптер с адресом, состоянием и текущим трафиком.")
        case .es:
            return Self(windowTitle: "Monitor de RyzenStatus", summary: "Visión general", processes: "Procesos",
                        processor: "Procesador", network: "Red", history: "Historial", diagnostics: "Diagnóstico",
                        section: "Sección", cores: "Núcleos", activeCoresFormat: "%d de %d activos",
                        pptLimitFormat: "Límite PPT: %@", voltage: "Voltaje", openMonitor: "Abrir Monitor",
                        openMonitorCaption: "El Dashboard se abre en su propia ventana.",
                        interfaceColumn: "Interfaz", addressColumn: "Dirección", statusColumn: "Estado",
                        statusUp: "Activa", statusDown: "Inactiva", metric: "Métrica",
                        cpuTemperature: "Temperatura de la CPU", gpuTemperature: "Temperatura de la GPU",
                        systemPower: "Consumo del sistema", averagePeakFormat: "Promedio %@, pico %@",
                        noHistory: "No hay datos para este periodo",
                        severityCritical: "Crítico", severityWarning: "Advertencia", severityInfo: "Información", viewMenu: "Visualización",
                        gpuColumn: "GPU %", chartTime: "Hora",
                        killUnavailable: "Esta app no se puede terminar ahora. Puede que se haya cerrado o reiniciado.",
                        cpuLoadFormat: "CPU — Usuario %@ · Sistema %@ · Total %@", ok: "Aceptar",
                        processGone: "Esta app ya no se está ejecutando, o su proceso ahora pertenece a otra app.",
                        hubDiagnosticsDescription: "Avisos de fugas de memoria, procesos desbocados, presión de memoria y CPU caliente.",
                        hubHistoryDescription: "Gráficos de CPU, GPU, memoria, red, disco, temperaturas y consumo de hasta 30 días.",
                        hubEnergyTitle: "Impacto energético", hubEnergyDescription: "Impacto energético estimado de cada app, según su parte de CPU y GPU.",
                        hubNetworkTitle: "Detalles de red", hubNetworkDescription: "Cada adaptador de red con su dirección, estado y tráfico en vivo.")
        case .de:
            return Self(windowTitle: "RyzenStatus-Monitor", summary: "Übersicht", processes: "Prozesse",
                        processor: "Prozessor", network: "Netzwerk", history: "Verlauf", diagnostics: "Diagnose",
                        section: "Bereich", cores: "Kerne", activeCoresFormat: "%d von %d aktiv",
                        pptLimitFormat: "PPT-Limit: %@", voltage: "Spannung", openMonitor: "Monitor öffnen",
                        openMonitorCaption: "Das Dashboard öffnet sich in einem eigenen Fenster.",
                        interfaceColumn: "Schnittstelle", addressColumn: "Adresse", statusColumn: "Status",
                        statusUp: "Aktiv", statusDown: "Inaktiv", metric: "Messwert",
                        cpuTemperature: "CPU-Temperatur", gpuTemperature: "GPU-Temperatur",
                        systemPower: "Systemleistung", averagePeakFormat: "Durchschnitt %@, Spitze %@",
                        noHistory: "Keine Daten für diesen Zeitraum",
                        severityCritical: "Kritisch", severityWarning: "Warnung", severityInfo: "Information", viewMenu: "Darstellung",
                        gpuColumn: "GPU %", chartTime: "Uhrzeit",
                        killUnavailable: "Diese App kann gerade nicht beendet werden. Sie wurde möglicherweise geschlossen oder neu gestartet.",
                        cpuLoadFormat: "CPU — Benutzer %@ · System %@ · Gesamt %@", ok: "OK",
                        processGone: "Diese App läuft nicht mehr, oder ihr Prozess gehört jetzt zu einer anderen App.",
                        hubDiagnosticsDescription: "Hinweise zu Speicherlecks, außer Kontrolle geratenen Prozessen, Speicherdruck und heißer CPU.",
                        hubHistoryDescription: "Diagramme zu CPU, GPU, Speicher, Netzwerk, Festplatte, Temperaturen und Leistung über bis zu 30 Tage.",
                        hubEnergyTitle: "Energieauswirkung", hubEnergyDescription: "Geschätzte Energieauswirkung jeder App aus ihrem CPU- und GPU-Anteil.",
                        hubNetworkTitle: "Netzwerkdetails", hubNetworkDescription: "Jeder Netzwerkadapter mit Adresse, Status und aktuellem Datenverkehr.")
        case .fr:
            return Self(windowTitle: "Moniteur RyzenStatus", summary: "Aperçu", processes: "Processus",
                        processor: "Processeur", network: "Réseau", history: "Historique", diagnostics: "Diagnostic",
                        section: "Section", cores: "Cœurs", activeCoresFormat: "%d sur %d actifs",
                        pptLimitFormat: "Limite PPT : %@", voltage: "Tension", openMonitor: "Ouvrir le moniteur",
                        openMonitorCaption: "Le tableau de bord s’ouvre dans sa propre fenêtre.",
                        interfaceColumn: "Interface", addressColumn: "Adresse", statusColumn: "État",
                        statusUp: "Active", statusDown: "Inactive", metric: "Mesure",
                        cpuTemperature: "Température du processeur", gpuTemperature: "Température du GPU",
                        systemPower: "Puissance du système", averagePeakFormat: "Moyenne %@, pic %@",
                        noHistory: "Aucune donnée pour cette période",
                        severityCritical: "Critique", severityWarning: "Avertissement", severityInfo: "Information", viewMenu: "Présentation",
                        gpuColumn: "GPU %", chartTime: "Heure",
                        killUnavailable: "Impossible de terminer cette app pour le moment. Elle a peut-être été fermée ou redémarrée.",
                        cpuLoadFormat: "Processeur — Utilisateur %@ · Système %@ · Total %@", ok: "OK",
                        processGone: "Cette app n’est plus en cours d’exécution, ou son processus appartient désormais à une autre app.",
                        hubDiagnosticsDescription: "Alertes pour les fuites de mémoire, les processus emballés, la pression mémoire et un processeur chaud.",
                        hubHistoryDescription: "Graphiques du processeur, du GPU, de la mémoire, du réseau, du disque, des températures et de la puissance sur 30 jours au plus.",
                        hubEnergyTitle: "Impact énergétique", hubEnergyDescription: "Impact énergétique estimé de chaque app, d’après sa part de processeur et de GPU.",
                        hubNetworkTitle: "Détails du réseau", hubNetworkDescription: "Chaque adaptateur réseau avec son adresse, son état et son trafic en direct.")
        case .it:
            return Self(windowTitle: "Monitor di RyzenStatus", summary: "Panoramica", processes: "Processi",
                        processor: "Processore", network: "Rete", history: "Cronologia", diagnostics: "Diagnostica",
                        section: "Sezione", cores: "Core", activeCoresFormat: "%d su %d attivi",
                        pptLimitFormat: "Limite PPT: %@", voltage: "Tensione", openMonitor: "Apri Monitor",
                        openMonitorCaption: "La dashboard si apre in una finestra a parte.",
                        interfaceColumn: "Interfaccia", addressColumn: "Indirizzo", statusColumn: "Stato",
                        statusUp: "Attiva", statusDown: "Inattiva", metric: "Misura",
                        cpuTemperature: "Temperatura CPU", gpuTemperature: "Temperatura GPU",
                        systemPower: "Potenza del sistema", averagePeakFormat: "Media %@, picco %@",
                        noHistory: "Nessun dato per questo periodo",
                        severityCritical: "Critico", severityWarning: "Avviso", severityInfo: "Informazione", viewMenu: "Vista",
                        gpuColumn: "GPU %", chartTime: "Ora",
                        killUnavailable: "Impossibile terminare questa app ora. Potrebbe essere stata chiusa o riavviata.",
                        cpuLoadFormat: "CPU — Utente %@ · Sistema %@ · Totale %@", ok: "OK",
                        processGone: "Questa app non è più in esecuzione, oppure il suo processo ora appartiene a un’altra app.",
                        hubDiagnosticsDescription: "Avvisi per perdite di memoria, processi fuori controllo, pressione della memoria e CPU calda.",
                        hubHistoryDescription: "Grafici di CPU, GPU, memoria, rete, disco, temperature e potenza fino a 30 giorni.",
                        hubEnergyTitle: "Impatto energetico", hubEnergyDescription: "Impatto energetico stimato di ogni app, in base alla sua quota di CPU e GPU.",
                        hubNetworkTitle: "Dettagli rete", hubNetworkDescription: "Ogni scheda di rete con indirizzo, stato e traffico in tempo reale.")
        case .ja:
            return Self(windowTitle: "RyzenStatus モニタ", summary: "概要", processes: "プロセス",
                        processor: "プロセッサ", network: "ネットワーク", history: "履歴", diagnostics: "診断",
                        section: "セクション", cores: "コア", activeCoresFormat: "%d / %d 稼働中",
                        pptLimitFormat: "PPT 上限: %@", voltage: "電圧", openMonitor: "モニタを開く",
                        openMonitorCaption: "ダッシュボードは専用のウインドウで開きます。",
                        interfaceColumn: "インターフェイス", addressColumn: "アドレス", statusColumn: "状態",
                        statusUp: "アクティブ", statusDown: "非アクティブ", metric: "項目",
                        cpuTemperature: "CPU 温度", gpuTemperature: "GPU 温度",
                        systemPower: "システム電力", averagePeakFormat: "平均 %@、最大 %@",
                        noHistory: "この期間のデータはありません",
                        severityCritical: "重大", severityWarning: "警告", severityInfo: "情報", viewMenu: "表示",
                        gpuColumn: "GPU %", chartTime: "時刻",
                        killUnavailable: "このアプリは今は終了できません。終了したか再起動した可能性があります。",
                        cpuLoadFormat: "CPU — ユーザ %@ · システム %@ · 合計 %@", ok: "OK",
                        processGone: "このアプリは実行されていないか、そのプロセスは別のアプリのものになっています。",
                        hubDiagnosticsDescription: "メモリリーク、暴走プロセス、メモリプレッシャー、CPU の高温を知らせます。",
                        hubHistoryDescription: "CPU、GPU、メモリ、ネットワーク、ディスク、温度、電力を最大 30 日分グラフで表示します。",
                        hubEnergyTitle: "エネルギー影響", hubEnergyDescription: "各アプリの CPU と GPU の使用率から推定したエネルギー影響。",
                        hubNetworkTitle: "ネットワークの詳細", hubNetworkDescription: "各ネットワークアダプタのアドレス、状態、現在の通信量。")
        case .ko:
            return Self(windowTitle: "RyzenStatus 모니터", summary: "개요", processes: "프로세스",
                        processor: "프로세서", network: "네트워크", history: "기록", diagnostics: "진단",
                        section: "섹션", cores: "코어", activeCoresFormat: "%d/%d 활성",
                        pptLimitFormat: "PPT 한도: %@", voltage: "전압", openMonitor: "모니터 열기",
                        openMonitorCaption: "대시보드는 별도의 윈도우에서 열립니다.",
                        interfaceColumn: "인터페이스", addressColumn: "주소", statusColumn: "상태",
                        statusUp: "활성", statusDown: "비활성", metric: "항목",
                        cpuTemperature: "CPU 온도", gpuTemperature: "GPU 온도",
                        systemPower: "시스템 전력", averagePeakFormat: "평균 %@, 최고 %@",
                        noHistory: "이 기간의 데이터가 없습니다",
                        severityCritical: "심각", severityWarning: "경고", severityInfo: "정보", viewMenu: "보기",
                        gpuColumn: "GPU %", chartTime: "시간",
                        killUnavailable: "지금은 이 앱을 종료할 수 없습니다. 이미 종료되었거나 다시 시작되었을 수 있습니다.",
                        cpuLoadFormat: "CPU — 사용자 %@ · 시스템 %@ · 전체 %@", ok: "확인",
                        processGone: "이 앱은 더 이상 실행 중이 아니거나, 해당 프로세스가 이제 다른 앱에 속해 있습니다.",
                        hubDiagnosticsDescription: "메모리 누수, 폭주하는 프로세스, 메모리 압력, 뜨거운 CPU를 알려 줍니다.",
                        hubHistoryDescription: "최대 30일간의 CPU, GPU, 메모리, 네트워크, 디스크, 온도, 전력 그래프.",
                        hubEnergyTitle: "에너지 영향", hubEnergyDescription: "각 앱의 CPU 및 GPU 사용 비율로 추정한 에너지 영향.",
                        hubNetworkTitle: "네트워크 세부 정보", hubNetworkDescription: "각 네트워크 어댑터의 주소, 상태, 실시간 트래픽.")
        case .zhHans:
            return Self(windowTitle: "RyzenStatus 监视器", summary: "概览", processes: "进程",
                        processor: "处理器", network: "网络", history: "历史记录", diagnostics: "诊断",
                        section: "部分", cores: "核心", activeCoresFormat: "%d/%d 活跃",
                        pptLimitFormat: "PPT 上限：%@", voltage: "电压", openMonitor: "打开监视器",
                        openMonitorCaption: "仪表板会在单独的窗口中打开。",
                        interfaceColumn: "接口", addressColumn: "地址", statusColumn: "状态",
                        statusUp: "活跃", statusDown: "未活跃", metric: "指标",
                        cpuTemperature: "CPU 温度", gpuTemperature: "GPU 温度",
                        systemPower: "系统功耗", averagePeakFormat: "平均 %@，峰值 %@",
                        noHistory: "此时段没有数据",
                        severityCritical: "严重", severityWarning: "警告", severityInfo: "信息", viewMenu: "显示",
                        gpuColumn: "GPU %", chartTime: "时间",
                        killUnavailable: "现在无法终止此应用。它可能已退出或重新启动。",
                        cpuLoadFormat: "CPU — 用户 %@ · 系统 %@ · 总计 %@", ok: "好",
                        processGone: "此应用已不再运行，或其进程现在属于另一个应用。",
                        hubDiagnosticsDescription: "提示内存泄漏、失控进程、内存压力和 CPU 过热。",
                        hubHistoryDescription: "最长 30 天的 CPU、GPU、内存、网络、磁盘、温度和功耗图表。",
                        hubEnergyTitle: "能耗影响", hubEnergyDescription: "根据每个应用的 CPU 和 GPU 占用估算的能耗影响。",
                        hubNetworkTitle: "网络详细信息", hubNetworkDescription: "每个网络适配器的地址、状态和实时流量。")
        case .zhTW:
            return Self(windowTitle: "RyzenStatus 監視器", summary: "概覽", processes: "程序",
                        processor: "處理器", network: "網路", history: "歷史記錄", diagnostics: "診斷",
                        section: "區段", cores: "核心", activeCoresFormat: "%d/%d 使用中",
                        pptLimitFormat: "PPT 上限：%@", voltage: "電壓", openMonitor: "打開監視器",
                        openMonitorCaption: "儀表板會在獨立的視窗中打開。",
                        interfaceColumn: "介面", addressColumn: "位址", statusColumn: "狀態",
                        statusUp: "使用中", statusDown: "未使用", metric: "項目",
                        cpuTemperature: "CPU 溫度", gpuTemperature: "GPU 溫度",
                        systemPower: "系統功耗", averagePeakFormat: "平均 %@，峰值 %@",
                        noHistory: "此期間沒有資料",
                        severityCritical: "嚴重", severityWarning: "警告", severityInfo: "資訊", viewMenu: "顯示方式",
                        gpuColumn: "GPU %", chartTime: "時間",
                        killUnavailable: "現在無法終止此 App。它可能已結束或重新啟動。",
                        cpuLoadFormat: "CPU — 使用者 %@ · 系統 %@ · 總計 %@", ok: "好",
                        processGone: "此 App 已不再執行，或其程序現在屬於另一個 App。",
                        hubDiagnosticsDescription: "提示記憶體洩漏、失控程序、記憶體壓力和 CPU 過熱。",
                        hubHistoryDescription: "最長 30 天的 CPU、GPU、記憶體、網路、磁碟、溫度和功耗圖表。",
                        hubEnergyTitle: "能耗影響", hubEnergyDescription: "依每個 App 的 CPU 和 GPU 佔用估算的能耗影響。",
                        hubNetworkTitle: "網路詳細資訊", hubNetworkDescription: "每個網路卡的位址、狀態和即時流量。")
        case .zhHK:
            return Self(windowTitle: "RyzenStatus 監視器", summary: "概覽", processes: "程序",
                        processor: "處理器", network: "網絡", history: "歷史記錄", diagnostics: "診斷",
                        section: "部分", cores: "核心", activeCoresFormat: "%d/%d 使用中",
                        pptLimitFormat: "PPT 上限：%@", voltage: "電壓", openMonitor: "打開監視器",
                        openMonitorCaption: "儀表板會在獨立的視窗中打開。",
                        interfaceColumn: "介面", addressColumn: "地址", statusColumn: "狀態",
                        statusUp: "使用中", statusDown: "未使用", metric: "項目",
                        cpuTemperature: "CPU 溫度", gpuTemperature: "GPU 溫度",
                        systemPower: "系統功耗", averagePeakFormat: "平均 %@，峰值 %@",
                        noHistory: "此期間沒有數據",
                        severityCritical: "嚴重", severityWarning: "警告", severityInfo: "資訊", viewMenu: "顯示方式",
                        gpuColumn: "GPU %", chartTime: "時間",
                        killUnavailable: "現在無法終止此 App。它可能已結束或重新啟動。",
                        cpuLoadFormat: "CPU — 用戶 %@ · 系統 %@ · 總計 %@", ok: "好",
                        processGone: "此 App 已不再執行，或其程序現在屬於另一個 App。",
                        hubDiagnosticsDescription: "提示記憶體洩漏、失控程序、記憶體壓力和 CPU 過熱。",
                        hubHistoryDescription: "最長 30 天的 CPU、GPU、記憶體、網絡、磁碟、溫度和功耗圖表。",
                        hubEnergyTitle: "能耗影響", hubEnergyDescription: "依每個 App 的 CPU 和 GPU 佔用估算的能耗影響。",
                        hubNetworkTitle: "網絡詳細資料", hubNetworkDescription: "每個網絡卡的地址、狀態和即時流量。")
        case .sk:
            return Self(windowTitle: "Monitor RyzenStatus", summary: "Prehľad", processes: "Procesy",
                        processor: "Procesor", network: "Sieť", history: "História", diagnostics: "Diagnostika",
                        section: "Sekcia", cores: "Jadrá", activeCoresFormat: "aktívne: %d z %d",
                        pptLimitFormat: "Limit PPT: %@", voltage: "Napätie", openMonitor: "Otvoriť Monitor",
                        openMonitorCaption: "Dashboard sa otvára vo vlastnom okne.",
                        interfaceColumn: "Rozhranie", addressColumn: "Adresa", statusColumn: "Stav",
                        statusUp: "Aktívne", statusDown: "Neaktívne", metric: "Veličina",
                        cpuTemperature: "Teplota CPU", gpuTemperature: "Teplota GPU",
                        systemPower: "Príkon systému", averagePeakFormat: "Priemer %@, špička %@",
                        noHistory: "Za toto obdobie nie sú žiadne údaje",
                        severityCritical: "Kritické", severityWarning: "Upozornenie", severityInfo: "Informácia", viewMenu: "Zobrazenie",
                        gpuColumn: "GPU %", chartTime: "Čas",
                        killUnavailable: "Túto aplikáciu teraz nemožno ukončiť. Mohla sa zavrieť alebo reštartovať.",
                        cpuLoadFormat: "CPU — Používateľ %@ · Systém %@ · Spolu %@", ok: "OK",
                        processGone: "Táto aplikácia už nebeží alebo jej proces teraz patrí inej aplikácii.",
                        hubDiagnosticsDescription: "Upozornenia na úniky pamäte, nekontrolované procesy, tlak na pamäť a horúci procesor.",
                        hubHistoryDescription: "Grafy CPU, GPU, pamäte, siete, disku, teplôt a príkonu až za 30 dní.",
                        hubEnergyTitle: "Energetický dopad", hubEnergyDescription: "Odhadovaný energetický dopad každej aplikácie podľa jej podielu CPU a GPU.",
                        hubNetworkTitle: "Podrobnosti siete", hubNetworkDescription: "Každý sieťový adaptér s adresou, stavom a aktuálnou prevádzkou.")
        case .uk:
            return Self(windowTitle: "Монітор RyzenStatus", summary: "Огляд", processes: "Процеси",
                        processor: "Процесор", network: "Мережа", history: "Історія", diagnostics: "Діагностика",
                        section: "Розділ", cores: "Ядра", activeCoresFormat: "активні: %d з %d",
                        pptLimitFormat: "Ліміт PPT: %@", voltage: "Напруга", openMonitor: "Відкрити монітор",
                        openMonitorCaption: "Панель відкривається в окремому вікні.",
                        interfaceColumn: "Інтерфейс", addressColumn: "Адреса", statusColumn: "Стан",
                        statusUp: "Активний", statusDown: "Неактивний", metric: "Показник",
                        cpuTemperature: "Температура ЦП", gpuTemperature: "Температура ГП",
                        systemPower: "Потужність системи", averagePeakFormat: "Середнє %@, пік %@",
                        noHistory: "Немає даних за цей період",
                        severityCritical: "Критично", severityWarning: "Попередження", severityInfo: "Інформація", viewMenu: "Вигляд",
                        gpuColumn: "GPU %", chartTime: "Час",
                        killUnavailable: "Цю програму зараз не можна завершити. Можливо, вона закрилася або перезапустилася.",
                        cpuLoadFormat: "ЦП — користувач %@ · система %@ · усього %@", ok: "OK",
                        processGone: "Ця програма більше не працює, або її процес тепер належить іншій програмі.",
                        hubDiagnosticsDescription: "Попередження про витоки пам’яті, некеровані процеси, тиск на пам’ять і гарячий ЦП.",
                        hubHistoryDescription: "Графіки ЦП, ГП, пам’яті, мережі, диска, температур і потужності за період до 30 днів.",
                        hubEnergyTitle: "Енерговплив", hubEnergyDescription: "Оцінка енерговпливу кожної програми за її часткою ЦП і ГП.",
                        hubNetworkTitle: "Відомості про мережу", hubNetworkDescription: "Кожен мережевий адаптер з адресою, станом і поточним трафіком.")
        }
    }
}
