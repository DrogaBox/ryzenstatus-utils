// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

struct PackageManagerStrings {
    let title: String
    let automatic: String
    let caption: String
    /// On Intel with no Homebrew installed: its installer refuses this Mac.
    let intelCaption: String
    let missing: String
    let privilege: String
    let handoff: String
    let queryFailed: String
    let compatibility: String
}

extension FeatureStrings {
    static func packageManager(_ language: AppLanguage) -> PackageManagerStrings {
        switch language {
        case .enUS: return PackageManagerStrings(
            title: "Package managers", automatic: "Automatic",
            caption: "MacPorts is preferred on Intel. Homebrew and its existing app installations remain available.",
            intelCaption: "The Homebrew installer only supports Apple Silicon, so this Mac uses MacPorts. A Homebrew already installed here can still be chosen.",
            missing: "MacPorts was not found at /opt/local/bin/port. Open the official installer; packages are never migrated automatically.",
            privilege: "This command opens in Terminal and may request your administrator password. Review it before continuing. Builds may take time.",
            handoff: "Command sent to Terminal, not completed. Refresh after it finishes.",
            queryFailed: "The package query failed, timed out, or exceeded its output limit.",
            compatibility: "Homebrew compatibility")
        case .es: return PackageManagerStrings(
            title: "Gestores de paquetes", automatic: "Automático",
            caption: "MacPorts es preferido en Intel. Homebrew y sus aplicaciones instaladas siguen disponibles.",
            intelCaption: "El instalador de Homebrew solo admite Apple Silicon, así que este Mac usa MacPorts. Si Homebrew ya estaba instalado, aún se puede elegir.",
            missing: "No se encontró MacPorts en /opt/local/bin/port. Abre el instalador oficial; nunca se migran paquetes automáticamente.",
            privilege: "El comando se abre en Terminal y puede pedir la contraseña de administrador. Revísalo antes de continuar. Las compilaciones pueden tardar.",
            handoff: "Comando enviado a Terminal, no completado. Actualiza la lista cuando termine.",
            queryFailed: "La consulta falló, agotó el tiempo o superó el límite de salida.",
            compatibility: "Compatibilidad con Homebrew")
        case .ptBR: return PackageManagerStrings(
            title: "Gerenciadores de pacotes", automatic: "Automático",
            caption: "O MacPorts é preferido no Intel. O Homebrew e seus aplicativos instalados continuam disponíveis.",
            intelCaption: "O instalador do Homebrew só oferece suporte a Apple Silicon, então este Mac usa o MacPorts. Um Homebrew já instalado ainda pode ser escolhido.",
            missing: "MacPorts não encontrado em /opt/local/bin/port. Abra o instalador oficial; pacotes nunca são migrados automaticamente.",
            privilege: "O comando abre no Terminal e pode pedir a senha de administrador. Revise antes de continuar. Compilações podem demorar.",
            handoff: "Comando enviado ao Terminal, não concluído. Atualize a lista quando terminar.",
            queryFailed: "A consulta falhou, expirou ou excedeu o limite de saída.",
            compatibility: "Compatibilidade com Homebrew")
        case .de: return PackageManagerStrings(
            title: "Paketmanager", automatic: "Automatisch",
            caption: "Auf Intel wird MacPorts bevorzugt. Homebrew und seine installierten Apps bleiben verfügbar.",
            intelCaption: "Das Homebrew-Installationsprogramm unterstützt nur Apple Silicon, daher nutzt dieser Mac MacPorts. Ein bereits installiertes Homebrew kann weiterhin gewählt werden.",
            missing: "MacPorts wurde unter /opt/local/bin/port nicht gefunden. Öffne den offiziellen Installer; Pakete werden nie automatisch migriert.",
            privilege: "Der Befehl wird im Terminal geöffnet und kann dein Administratorpasswort anfordern. Prüfe ihn zuerst. Builds können dauern.",
            handoff: "Befehl an Terminal gesendet, nicht abgeschlossen. Aktualisiere die Liste nach Abschluss.",
            queryFailed: "Die Abfrage ist fehlgeschlagen, hat das Zeitlimit oder das Ausgabelimit überschritten.",
            compatibility: "Homebrew-Kompatibilität")
        case .fr: return PackageManagerStrings(
            title: "Gestionnaires de paquets", automatic: "Automatique",
            caption: "MacPorts est privilégié sur Intel. Homebrew et ses apps installées restent disponibles.",
            intelCaption: "L’installateur de Homebrew ne prend en charge que les puces Apple, ce Mac utilise donc MacPorts. Un Homebrew déjà installé peut toujours être choisi.",
            missing: "MacPorts est introuvable à /opt/local/bin/port. Ouvrez l’installateur officiel ; aucun paquet n’est migré automatiquement.",
            privilege: "La commande s’ouvre dans Terminal et peut demander votre mot de passe administrateur. Vérifiez-la d’abord. La compilation peut être longue.",
            handoff: "Commande envoyée à Terminal, pas terminée. Actualisez la liste après son exécution.",
            queryFailed: "La requête a échoué ou dépassé sa limite de temps ou de sortie.",
            compatibility: "Compatibilité Homebrew")
        case .it: return PackageManagerStrings(
            title: "Gestori di pacchetti", automatic: "Automatico",
            caption: "MacPorts è preferito su Intel. Homebrew e le sue app installate restano disponibili.",
            intelCaption: "Il programma di installazione di Homebrew supporta solo Apple Silicon, quindi questo Mac usa MacPorts. Un Homebrew già installato si può ancora scegliere.",
            missing: "MacPorts non trovato in /opt/local/bin/port. Apri l’installer ufficiale; i pacchetti non vengono mai migrati automaticamente.",
            privilege: "Il comando si apre in Terminale e può richiedere la password amministratore. Controllalo prima. La compilazione può richiedere tempo.",
            handoff: "Comando inviato a Terminale, non completato. Aggiorna l’elenco al termine.",
            queryFailed: "La richiesta è fallita o ha superato il limite di tempo o di output.",
            compatibility: "Compatibilità Homebrew")
        case .sk: return PackageManagerStrings(
            title: "Správcovia balíkov", automatic: "Automaticky",
            caption: "Na Intel sa uprednostňuje MacPorts. Homebrew a jeho nainštalované aplikácie zostávajú dostupné.",
            intelCaption: "Inštalátor Homebrew podporuje iba Apple Silicon, preto tento Mac používa MacPorts. Už nainštalovaný Homebrew sa dá stále zvoliť.",
            missing: "MacPorts sa nenašiel v /opt/local/bin/port. Otvorte oficiálny inštalátor; balíky sa nikdy nemigrujú automaticky.",
            privilege: "Príkaz sa otvorí v Termináli a môže vyžiadať heslo správcu. Najprv ho skontrolujte. Kompilácia môže trvať dlhšie.",
            handoff: "Príkaz bol odoslaný do Terminálu, nie dokončený. Po dokončení obnovte zoznam.",
            queryFailed: "Dotaz zlyhal alebo prekročil časový limit či limit výstupu.",
            compatibility: "Kompatibilita s Homebrew")
        case .uk: return PackageManagerStrings(
            title: "Менеджери пакунків", automatic: "Автоматично",
            caption: "На Intel перевага надається MacPorts. Homebrew та його встановлені програми залишаються доступними.",
            intelCaption: "Інсталятор Homebrew підтримує лише Apple Silicon, тож цей Mac використовує MacPorts. Уже встановлений Homebrew усе ще можна вибрати.",
            missing: "MacPorts не знайдено в /opt/local/bin/port. Відкрийте офіційний інсталятор; пакунки ніколи не переносяться автоматично.",
            privilege: "Команда відкриється в Терміналі й може попросити пароль адміністратора. Спочатку перевірте її. Компіляція може тривати довго.",
            handoff: "Команду надіслано до Терміналу, але не завершено. Оновіть список після завершення.",
            queryFailed: "Запит не вдався або перевищив ліміт часу чи виводу.",
            compatibility: "Сумісність із Homebrew")
        case .ru: return PackageManagerStrings(
            title: "Менеджеры пакетов", automatic: "Автоматически",
            caption: "На Intel предпочтителен MacPorts. Homebrew и его установленные приложения остаются доступны.",
            intelCaption: "Установщик Homebrew поддерживает только Apple Silicon, поэтому этот Mac использует MacPorts. Уже установленный Homebrew по-прежнему можно выбрать.",
            missing: "MacPorts не найден в /opt/local/bin/port. Откройте официальный установщик; пакеты никогда не переносятся автоматически.",
            privilege: "Команда откроется в Терминале и может запросить пароль администратора. Сначала проверьте её. Компиляция может занять время.",
            handoff: "Команда отправлена в Терминал, но не завершена. Обновите список после завершения.",
            queryFailed: "Запрос не удался или превысил ограничение времени или вывода.",
            compatibility: "Совместимость с Homebrew")
        case .tr: return PackageManagerStrings(
            title: "Paket yöneticileri", automatic: "Otomatik",
            caption: "Intel’de MacPorts tercih edilir. Homebrew ve yüklü uygulamaları kullanılabilir kalır.",
            intelCaption: "Homebrew yükleyicisi yalnızca Apple Silicon’ı destekler, bu yüzden bu Mac MacPorts kullanır. Zaten yüklü bir Homebrew yine de seçilebilir.",
            missing: "MacPorts /opt/local/bin/port konumunda bulunamadı. Resmî yükleyiciyi açın; paketler otomatik taşınmaz.",
            privilege: "Komut Terminal’de açılır ve yönetici parolanızı isteyebilir. Önce gözden geçirin. Derleme zaman alabilir.",
            handoff: "Komut Terminal’e gönderildi, tamamlanmadı. Bittikten sonra listeyi yenileyin.",
            queryFailed: "Sorgu başarısız oldu ya da süre veya çıktı sınırını aştı.",
            compatibility: "Homebrew uyumluluğu")
        case .ja: return PackageManagerStrings(
            title: "パッケージマネージャー", automatic: "自動",
            caption: "IntelではMacPortsを優先します。Homebrewと既存のアプリは引き続き利用できます。",
            intelCaption: "Homebrew のインストーラは Apple シリコンのみに対応しているため、この Mac では MacPorts を使います。すでにインストール済みの Homebrew は引き続き選べます。",
            missing: "/opt/local/bin/portにMacPortsが見つかりません。公式インストーラーを開いてください。パッケージは自動移行されません。",
            privilege: "コマンドはターミナルで開き、管理者パスワードを要求する場合があります。まず内容を確認してください。ビルドには時間がかかる場合があります。",
            handoff: "ターミナルにコマンドを送りましたが、完了していません。終了後に一覧を更新してください。",
            queryFailed: "照会が失敗したか、時間または出力の制限を超えました。",
            compatibility: "Homebrew互換性")
        case .ko: return PackageManagerStrings(
            title: "패키지 관리자", automatic: "자동",
            caption: "Intel에서는 MacPorts를 우선합니다. Homebrew와 기존 앱은 계속 사용할 수 있습니다.",
            intelCaption: "Homebrew 설치 프로그램은 Apple 실리콘만 지원하므로 이 Mac은 MacPorts를 사용합니다. 이미 설치된 Homebrew는 계속 선택할 수 있습니다.",
            missing: "/opt/local/bin/port에서 MacPorts를 찾지 못했습니다. 공식 설치 프로그램을 여세요. 패키지는 자동으로 이전되지 않습니다.",
            privilege: "명령은 터미널에서 열리며 관리자 암호를 요청할 수 있습니다. 먼저 확인하세요. 빌드에 시간이 걸릴 수 있습니다.",
            handoff: "명령을 터미널로 보냈으나 완료되지 않았습니다. 종료 후 목록을 새로 고치세요.",
            queryFailed: "조회에 실패했거나 시간 또는 출력 제한을 초과했습니다.",
            compatibility: "Homebrew 호환성")
        case .zhHans: return PackageManagerStrings(
            title: "软件包管理器", automatic: "自动",
            caption: "Intel 上优先使用 MacPorts。Homebrew 及其已安装的应用仍可使用。",
            intelCaption: "Homebrew 安装程序仅支持 Apple 芯片，因此这台 Mac 使用 MacPorts。已安装的 Homebrew 仍可选择。",
            missing: "在 /opt/local/bin/port 未找到 MacPorts。请打开官方安装程序；软件包不会自动迁移。",
            privilege: "命令将在终端中打开，可能要求管理员密码。请先检查。编译可能需要较长时间。",
            handoff: "命令已发送到终端，但尚未完成。结束后请刷新列表。",
            queryFailed: "查询失败，或超出了时间或输出限制。",
            compatibility: "Homebrew 兼容性")
        case .zhTW: return PackageManagerStrings(
            title: "套件管理員", automatic: "自動",
            caption: "Intel 上優先使用 MacPorts。Homebrew 及其已安裝的應用程式仍可使用。",
            intelCaption: "Homebrew 安裝程式僅支援 Apple 晶片，因此這台 Mac 使用 MacPorts。已安裝的 Homebrew 仍可選擇。",
            missing: "在 /opt/local/bin/port 找不到 MacPorts。請開啟官方安裝程式；套件不會自動移轉。",
            privilege: "指令將在終端機中開啟，可能要求管理員密碼。請先檢查。編譯可能需要較長時間。",
            handoff: "指令已傳送到終端機，但尚未完成。結束後請重新整理清單。",
            queryFailed: "查詢失敗，或超出了時間或輸出限制。",
            compatibility: "Homebrew 相容性")
        case .zhHK: return PackageManagerStrings(
            title: "套件管理器", automatic: "自動",
            caption: "Intel 上優先使用 MacPorts。Homebrew 及其已安裝的應用程式仍可使用。",
            intelCaption: "Homebrew 安裝程式只支援 Apple 晶片，所以這部 Mac 使用 MacPorts。已安裝的 Homebrew 仍可選擇。",
            missing: "在 /opt/local/bin/port 找不到 MacPorts。請開啟官方安裝程式；套件不會自動遷移。",
            privilege: "指令將在終端機開啟，可能要求管理員密碼。請先檢查。編譯可能需時。",
            handoff: "指令已傳送至終端機，但尚未完成。結束後請重新整理清單。",
            queryFailed: "查詢失敗，或超出了時間或輸出限制。",
            compatibility: "Homebrew 相容性")
        }
    }
}
