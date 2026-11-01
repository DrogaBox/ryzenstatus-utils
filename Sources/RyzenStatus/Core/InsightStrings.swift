// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus
import Foundation
/// Strings for the diagnostic cards InsightEngine builds. Same contract as
/// the other FeatureStrings structs: memberwise init with labeled arguments in
/// declaration order, one static per language, all in this file.
struct InsightStrings {
    let leakTitleFormat: String
    let leakDetail: String
    let leakHint: String
    let cpuTitleFormat: String
    let cpuDetailFormat: String
    let cpuHint: String
    let criticalPressure: String
    let elevatedPressure: String
    let pressureDetail: String
    let pressureHint: String
    let rosettaTitle: String
    let rosettaDetailFormat: String
    let rosettaHint: String
    let tempTitleFormat: String
    let tempDetail: String
    let tempHint: String
    let categoryMemory: String
    let categoryCPU: String
    let categoryArchitecture: String
    let categoryThermal: String
}
extension FeatureStrings {
    static func insights(_ language: AppLanguage) -> InsightStrings {
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
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}
private extension InsightStrings {
    static let enUS = InsightStrings(
        leakTitleFormat: "%@: possible memory leak",
        leakDetail: "Its memory has kept growing for more than 20 minutes at a steady rate (R² ≥ 0.85).",
        leakHint: "Inspect the process or force it to quit",
        cpuTitleFormat: "%@: high CPU load",
        cpuDetailFormat: "Using %@ of the CPU.",
        cpuHint: "Check that the app still responds",
        criticalPressure: "Critical memory pressure",
        elevatedPressure: "Elevated memory pressure",
        pressureDetail: "macOS is compressing memory or swapping to disk. Close apps you are not using to get the speed back.",
        pressureHint: "Close heavy apps",
        rosettaTitle: "Rosetta 2 translation running",
        rosettaDetailFormat: "Intel apps running through translation: %d (%@).",
        rosettaHint: "Install native or Universal versions if they exist",
        tempTitleFormat: "High CPU temperature (%@)",
        tempDetail: "The processor may slow itself down if it stays this hot under sustained load.",
        tempHint: "Check the airflow or lighten the workload",
        categoryMemory: "Memory",
        categoryCPU: "CPU",
        categoryArchitecture: "Architecture",
        categoryThermal: "Thermal"
    )

    static let ptBR = InsightStrings(
        leakTitleFormat: "%@: possível vazamento de memória",
        leakDetail: "A memória dele cresce há mais de 20 minutos em ritmo constante (R² ≥ 0,85).",
        leakHint: "Inspecione o processo ou force o encerramento",
        cpuTitleFormat: "%@: carga de CPU alta",
        cpuDetailFormat: "Usando %@ da CPU.",
        cpuHint: "Verifique se o app ainda responde",
        criticalPressure: "Pressão de memória crítica",
        elevatedPressure: "Pressão de memória elevada",
        pressureDetail: "O macOS está comprimindo memória ou usando o disco como swap. Feche os apps que não está usando para recuperar a velocidade.",
        pressureHint: "Feche os apps pesados",
        rosettaTitle: "Tradução do Rosetta 2 em uso",
        rosettaDetailFormat: "Apps Intel rodando por tradução: %d (%@).",
        rosettaHint: "Instale versões nativas ou Universais, se existirem",
        tempTitleFormat: "Temperatura da CPU alta (%@)",
        tempDetail: "O processador pode reduzir a velocidade se continuar tão quente sob carga contínua.",
        tempHint: "Verifique a ventilação ou reduza a carga de trabalho",
        categoryMemory: "Memória",
        categoryCPU: "CPU",
        categoryArchitecture: "Arquitetura",
        categoryThermal: "Temperatura"
    )

    static let tr = InsightStrings(
        leakTitleFormat: "%@: olası bellek sızıntısı",
        leakDetail: "Belleği 20 dakikadan uzun süredir sabit hızla büyüyor (R² ≥ 0,85).",
        leakHint: "İşlemi incele veya zorla kapat",
        cpuTitleFormat: "%@: yüksek CPU yükü",
        cpuDetailFormat: "CPU'nun %@ kadarını kullanıyor.",
        cpuHint: "Uygulamanın hâlâ yanıt verdiğini kontrol et",
        criticalPressure: "Kritik bellek baskısı",
        elevatedPressure: "Yüksek bellek baskısı",
        pressureDetail: "macOS belleği sıkıştırıyor veya diske takas yapıyor. Hızı geri kazanmak için kullanmadığın uygulamaları kapat.",
        pressureHint: "Ağır uygulamaları kapat",
        rosettaTitle: "Rosetta 2 çevirisi çalışıyor",
        rosettaDetailFormat: "Çeviriyle çalışan Intel uygulamaları: %d (%@).",
        rosettaHint: "Varsa yerel veya Universal sürümleri yükle",
        tempTitleFormat: "Yüksek CPU sıcaklığı (%@)",
        tempDetail: "Sürekli yük altında bu kadar sıcak kalırsa işlemci kendini yavaşlatabilir.",
        tempHint: "Hava akışını kontrol et veya yükü azalt",
        categoryMemory: "Bellek",
        categoryCPU: "CPU",
        categoryArchitecture: "Mimari",
        categoryThermal: "Sıcaklık"
    )

    static let ru = InsightStrings(
        leakTitleFormat: "%@: возможная утечка памяти",
        leakDetail: "Его память равномерно растёт уже больше 20 минут (R² ≥ 0,85).",
        leakHint: "Проверьте процесс или завершите его принудительно",
        cpuTitleFormat: "%@: высокая нагрузка на ЦП",
        cpuDetailFormat: "Использует %@ ЦП.",
        cpuHint: "Проверьте, отвечает ли приложение",
        criticalPressure: "Критическая нагрузка на память",
        elevatedPressure: "Повышенная нагрузка на память",
        pressureDetail: "macOS сжимает память или использует диск для подкачки. Закройте ненужные приложения, чтобы вернуть скорость.",
        pressureHint: "Закройте тяжёлые приложения",
        rosettaTitle: "Работает трансляция Rosetta 2",
        rosettaDetailFormat: "Приложений Intel через трансляцию: %d (%@).",
        rosettaHint: "Установите нативные или универсальные версии, если они есть",
        tempTitleFormat: "Высокая температура ЦП (%@)",
        tempDetail: "Процессор может снизить частоту, если будет так греться под долгой нагрузкой.",
        tempHint: "Проверьте обдув или снизьте нагрузку",
        categoryMemory: "Память",
        categoryCPU: "ЦП",
        categoryArchitecture: "Архитектура",
        categoryThermal: "Температура"
    )

    static let es = InsightStrings(
        leakTitleFormat: "%@: posible fuga de memoria",
        leakDetail: "Su memoria lleva más de 20 minutos creciendo a un ritmo constante (R² ≥ 0,85).",
        leakHint: "Inspecciona el proceso o fuerza su salida",
        cpuTitleFormat: "%@: carga de CPU alta",
        cpuDetailFormat: "Usa el %@ de la CPU.",
        cpuHint: "Comprueba que la app siga respondiendo",
        criticalPressure: "Presión de memoria crítica",
        elevatedPressure: "Presión de memoria elevada",
        pressureDetail: "macOS está comprimiendo memoria o usando el disco como intercambio. Cierra las apps que no uses para recuperar velocidad.",
        pressureHint: "Cierra las apps pesadas",
        rosettaTitle: "Traducción de Rosetta 2 activa",
        rosettaDetailFormat: "Apps de Intel ejecutándose con traducción: %d (%@).",
        rosettaHint: "Instala versiones nativas o universales si existen",
        tempTitleFormat: "Temperatura de CPU alta (%@)",
        tempDetail: "El procesador puede bajar su velocidad si sigue tan caliente con carga sostenida.",
        tempHint: "Revisa la ventilación o reduce la carga de trabajo",
        categoryMemory: "Memoria",
        categoryCPU: "CPU",
        categoryArchitecture: "Arquitectura",
        categoryThermal: "Temperatura"
    )

    static let de = InsightStrings(
        leakTitleFormat: "%@: mögliches Speicherleck",
        leakDetail: "Sein Speicher wächst seit über 20 Minuten gleichmäßig (R² ≥ 0,85).",
        leakHint: "Prozess untersuchen oder sofort beenden",
        cpuTitleFormat: "%@: hohe CPU-Last",
        cpuDetailFormat: "Belegt %@ der CPU.",
        cpuHint: "Prüfen, ob die App noch reagiert",
        criticalPressure: "Kritische Speicherauslastung",
        elevatedPressure: "Erhöhte Speicherauslastung",
        pressureDetail: "macOS komprimiert Speicher oder lagert auf die Festplatte aus. Schließe nicht benötigte Apps, um wieder schneller zu werden.",
        pressureHint: "Speicherhungrige Apps schließen",
        rosettaTitle: "Rosetta-2-Übersetzung aktiv",
        rosettaDetailFormat: "Intel-Apps mit Übersetzung: %d (%@).",
        rosettaHint: "Native oder Universal-Versionen installieren, falls vorhanden",
        tempTitleFormat: "Hohe CPU-Temperatur (%@)",
        tempDetail: "Der Prozessor kann sich drosseln, wenn er unter Dauerlast so heiß bleibt.",
        tempHint: "Luftstrom prüfen oder Last verringern",
        categoryMemory: "Speicher",
        categoryCPU: "CPU",
        categoryArchitecture: "Architektur",
        categoryThermal: "Temperatur"
    )

    static let fr = InsightStrings(
        leakTitleFormat: "%@ : fuite de mémoire possible",
        leakDetail: "Sa mémoire augmente à un rythme régulier depuis plus de 20 minutes (R² ≥ 0,85).",
        leakHint: "Inspecter le processus ou forcer sa fermeture",
        cpuTitleFormat: "%@ : charge CPU élevée",
        cpuDetailFormat: "Utilise %@ du CPU.",
        cpuHint: "Vérifiez que l’app répond encore",
        criticalPressure: "Pression mémoire critique",
        elevatedPressure: "Pression mémoire élevée",
        pressureDetail: "macOS compresse la mémoire ou utilise le disque comme swap. Fermez les apps inutilisées pour retrouver de la vitesse.",
        pressureHint: "Fermer les apps gourmandes",
        rosettaTitle: "Traduction Rosetta 2 en cours",
        rosettaDetailFormat: "Apps Intel exécutées par traduction : %d (%@).",
        rosettaHint: "Installez des versions natives ou universelles si elles existent",
        tempTitleFormat: "Température CPU élevée (%@)",
        tempDetail: "Le processeur peut ralentir s’il reste aussi chaud sous charge prolongée.",
        tempHint: "Vérifiez la ventilation ou allégez la charge",
        categoryMemory: "Mémoire",
        categoryCPU: "CPU",
        categoryArchitecture: "Architecture",
        categoryThermal: "Température"
    )

    static let it = InsightStrings(
        leakTitleFormat: "%@: possibile perdita di memoria",
        leakDetail: "La sua memoria cresce a ritmo costante da oltre 20 minuti (R² ≥ 0,85).",
        leakHint: "Ispeziona il processo o forzane l'uscita",
        cpuTitleFormat: "%@: carico CPU elevato",
        cpuDetailFormat: "Usa il %@ della CPU.",
        cpuHint: "Controlla che l'app risponda ancora",
        criticalPressure: "Pressione della memoria critica",
        elevatedPressure: "Pressione della memoria elevata",
        pressureDetail: "macOS sta comprimendo la memoria o usando il disco come swap. Chiudi le app che non usi per recuperare velocità.",
        pressureHint: "Chiudi le app pesanti",
        rosettaTitle: "Traduzione Rosetta 2 attiva",
        rosettaDetailFormat: "App Intel in esecuzione tramite traduzione: %d (%@).",
        rosettaHint: "Installa versioni native o Universal, se disponibili",
        tempTitleFormat: "Temperatura CPU elevata (%@)",
        tempDetail: "Il processore può rallentare se resta così caldo sotto carico prolungato.",
        tempHint: "Controlla il flusso d'aria o riduci il carico",
        categoryMemory: "Memoria",
        categoryCPU: "CPU",
        categoryArchitecture: "Architettura",
        categoryThermal: "Temperatura"
    )

    static let ja = InsightStrings(
        leakTitleFormat: "%@：メモリリークの可能性",
        leakDetail: "20 分以上にわたりメモリが一定のペースで増え続けています（R² ≥ 0.85）。",
        leakHint: "プロセスを調べるか強制終了してください",
        cpuTitleFormat: "%@：CPU 負荷が高い",
        cpuDetailFormat: "CPU を %@ 使用しています。",
        cpuHint: "アプリが応答しているか確認してください",
        criticalPressure: "メモリプレッシャーが危険な状態",
        elevatedPressure: "メモリプレッシャーが高い",
        pressureDetail: "macOS がメモリを圧縮するかディスクにスワップしています。使っていないアプリを終了すると速度が戻ります。",
        pressureHint: "重いアプリを終了する",
        rosettaTitle: "Rosetta 2 による変換が動作中",
        rosettaDetailFormat: "変換で動作中の Intel アプリ：%d（%@）。",
        rosettaHint: "ネイティブ版またはユニバーサル版があればインストールしてください",
        tempTitleFormat: "CPU 温度が高い（%@）",
        tempDetail: "高負荷が続いてこの温度のままだと、プロセッサが速度を落とすことがあります。",
        tempHint: "エアフローを確認するか負荷を減らしてください",
        categoryMemory: "メモリ",
        categoryCPU: "CPU",
        categoryArchitecture: "アーキテクチャ",
        categoryThermal: "温度"
    )

    static let ko = InsightStrings(
        leakTitleFormat: "%@: 메모리 누수 가능성",
        leakDetail: "20분 넘게 메모리가 일정한 속도로 계속 늘고 있습니다(R² ≥ 0.85).",
        leakHint: "프로세스를 살펴보거나 강제 종료하세요",
        cpuTitleFormat: "%@: 높은 CPU 부하",
        cpuDetailFormat: "CPU의 %@을(를) 사용 중입니다.",
        cpuHint: "앱이 응답하는지 확인하세요",
        criticalPressure: "심각한 메모리 압박",
        elevatedPressure: "높은 메모리 압박",
        pressureDetail: "macOS가 메모리를 압축하거나 디스크로 스왑하고 있습니다. 사용하지 않는 앱을 닫으면 속도가 돌아옵니다.",
        pressureHint: "무거운 앱 닫기",
        rosettaTitle: "Rosetta 2 변환 실행 중",
        rosettaDetailFormat: "변환으로 실행 중인 Intel 앱: %d개(%@).",
        rosettaHint: "네이티브 또는 유니버설 버전이 있으면 설치하세요",
        tempTitleFormat: "높은 CPU 온도(%@)",
        tempDetail: "지속 부하에서 이 온도가 계속되면 프로세서가 속도를 낮출 수 있습니다.",
        tempHint: "공기 흐름을 확인하거나 작업량을 줄이세요",
        categoryMemory: "메모리",
        categoryCPU: "CPU",
        categoryArchitecture: "아키텍처",
        categoryThermal: "온도"
    )

    static let zhHans = InsightStrings(
        leakTitleFormat: "%@：可能存在内存泄漏",
        leakDetail: "其内存已持续稳定增长超过 20 分钟（R² ≥ 0.85）。",
        leakHint: "检查该进程或强制退出",
        cpuTitleFormat: "%@：CPU 负载高",
        cpuDetailFormat: "占用 %@ 的 CPU。",
        cpuHint: "检查应用是否仍有响应",
        criticalPressure: "内存压力严重",
        elevatedPressure: "内存压力偏高",
        pressureDetail: "macOS 正在压缩内存或将数据交换到磁盘。关闭不用的应用即可恢复速度。",
        pressureHint: "关闭占用大的应用",
        rosettaTitle: "Rosetta 2 转译运行中",
        rosettaDetailFormat: "通过转译运行的 Intel 应用：%d 个（%@）。",
        rosettaHint: "如有原生或通用版本，请安装",
        tempTitleFormat: "CPU 温度过高（%@）",
        tempDetail: "如果在持续负载下一直这么热，处理器可能会降频。",
        tempHint: "检查散热气流或减轻负载",
        categoryMemory: "内存",
        categoryCPU: "CPU",
        categoryArchitecture: "架构",
        categoryThermal: "温度"
    )

    static let zhTW = InsightStrings(
        leakTitleFormat: "%@：可能有記憶體洩漏",
        leakDetail: "其記憶體已持續穩定增加超過 20 分鐘（R² ≥ 0.85）。",
        leakHint: "檢查該程序或強制結束",
        cpuTitleFormat: "%@：CPU 負載高",
        cpuDetailFormat: "使用 %@ 的 CPU。",
        cpuHint: "確認 App 是否仍有回應",
        criticalPressure: "記憶體壓力嚴重",
        elevatedPressure: "記憶體壓力偏高",
        pressureDetail: "macOS 正在壓縮記憶體或將資料置換到磁碟。關閉不用的 App 即可恢復速度。",
        pressureHint: "關閉耗用大的 App",
        rosettaTitle: "Rosetta 2 轉譯執行中",
        rosettaDetailFormat: "透過轉譯執行的 Intel App：%d 個（%@）。",
        rosettaHint: "如有原生或通用版本，請安裝",
        tempTitleFormat: "CPU 溫度過高（%@）",
        tempDetail: "如果在持續負載下一直這麼熱，處理器可能會降頻。",
        tempHint: "檢查散熱氣流或減輕負載",
        categoryMemory: "記憶體",
        categoryCPU: "CPU",
        categoryArchitecture: "架構",
        categoryThermal: "溫度"
    )

    static let zhHK = zhTW

    static let sk = InsightStrings(
        leakTitleFormat: "%@: možný únik pamäte",
        leakDetail: "Jeho pamäť už viac ako 20 minút rovnomerne rastie (R² ≥ 0,85).",
        leakHint: "Preskúmajte proces alebo ho vynútene ukončite",
        cpuTitleFormat: "%@: vysoké zaťaženie CPU",
        cpuDetailFormat: "Využíva %@ CPU.",
        cpuHint: "Skontrolujte, či aplikácia stále reaguje",
        criticalPressure: "Kritické zaťaženie pamäte",
        elevatedPressure: "Zvýšené zaťaženie pamäte",
        pressureDetail: "macOS komprimuje pamäť alebo odkladá na disk. Zatvorte nepoužívané aplikácie, aby sa vrátila rýchlosť.",
        pressureHint: "Zatvorte náročné aplikácie",
        rosettaTitle: "Beží preklad Rosetta 2",
        rosettaDetailFormat: "Aplikácie Intel cez preklad: %d (%@).",
        rosettaHint: "Nainštalujte natívne alebo univerzálne verzie, ak existujú",
        tempTitleFormat: "Vysoká teplota CPU (%@)",
        tempDetail: "Procesor sa môže spomaliť, ak zostane takto horúci pri dlhšej záťaži.",
        tempHint: "Skontrolujte prúdenie vzduchu alebo znížte záťaž",
        categoryMemory: "Pamäť",
        categoryCPU: "CPU",
        categoryArchitecture: "Architektúra",
        categoryThermal: "Teplota"
    )

    static let uk = InsightStrings(
        leakTitleFormat: "%@: можливий витік пам'яті",
        leakDetail: "Його пам'ять рівномірно зростає вже понад 20 хвилин (R² ≥ 0,85).",
        leakHint: "Перевірте процес або завершіть його примусово",
        cpuTitleFormat: "%@: високе навантаження на ЦП",
        cpuDetailFormat: "Використовує %@ ЦП.",
        cpuHint: "Перевірте, чи відповідає програма",
        criticalPressure: "Критичне навантаження на пам'ять",
        elevatedPressure: "Підвищене навантаження на пам'ять",
        pressureDetail: "macOS стискає пам'ять або використовує диск для підкачки. Закрийте непотрібні програми, щоб повернути швидкість.",
        pressureHint: "Закрийте важкі програми",
        rosettaTitle: "Працює трансляція Rosetta 2",
        rosettaDetailFormat: "Програм Intel через трансляцію: %d (%@).",
        rosettaHint: "Установіть нативні або універсальні версії, якщо вони є",
        tempTitleFormat: "Висока температура ЦП (%@)",
        tempDetail: "Процесор може знизити частоту, якщо так грітиметься під тривалим навантаженням.",
        tempHint: "Перевірте обдув або зменште навантаження",
        categoryMemory: "Пам'ять",
        categoryCPU: "ЦП",
        categoryArchitecture: "Архітектура",
        categoryThermal: "Температура"
    )
}
