// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

/// The Advanced page's "repair permissions" section.
struct PermissionRepairStrings {
    let title: String
    let description: String
    let button: String
    /// `%d`: how many permissions were tied again.
    let repairedFormat: String
    let nothingToRepair: String
    let needsFullDiskAccess: String
    let openFullDiskAccess: String
    let failed: String
    let relaunch: String
}

extension FeatureStrings {
    static func permissionRepair(_ language: AppLanguage) -> PermissionRepairStrings {
        switch language {
        case .enUS:
            return .init(title: "Repair permissions",
                         description: "After an update, macOS can keep a permission switched on while it no longer applies to the new version: the microphone, system audio, camera, calendars or Automation stop working. This ties the permissions you already gave back to the installed version. It never grants anything new. It needs Full Disk Access.",
                         button: "Repair permissions",
                         repairedFormat: "Permissions tied again: %d. Restart RyzenStatus to use them.",
                         nothingToRepair: "Nothing to repair: every permission you gave applies to this version.",
                         needsFullDiskAccess: "RyzenStatus needs Full Disk Access to read the permission list. Turn it on, restart the app and try again.",
                         openFullDiskAccess: "Open Full Disk Access",
                         failed: "The permissions could not be repaired.",
                         relaunch: "Restart RyzenStatus")
        case .ptBR:
            return .init(title: "Reparar permissões",
                         description: "Depois de uma atualização, o macOS pode manter uma permissão ativada sem que ela valha para a nova versão: o microfone, o áudio do sistema, a câmera, os calendários ou a Automação param de funcionar. Isto vincula as permissões que você já deu à versão instalada. Nunca concede nada novo. Requer Acesso Total ao Disco.",
                         button: "Reparar permissões",
                         repairedFormat: "Permissões vinculadas de novo: %d. Reinicie o RyzenStatus para usá-las.",
                         nothingToRepair: "Nada a reparar: todas as permissões que você deu valem para esta versão.",
                         needsFullDiskAccess: "O RyzenStatus precisa de Acesso Total ao Disco para ler a lista de permissões. Ative-o, reinicie o app e tente de novo.",
                         openFullDiskAccess: "Abrir Acesso Total ao Disco",
                         failed: "Não foi possível reparar as permissões.",
                         relaunch: "Reiniciar o RyzenStatus")
        case .tr:
            return .init(title: "İzinleri onar",
                         description: "Bir güncellemeden sonra macOS bir izni açık gösterip yeni sürüm için geçersiz bırakabilir: mikrofon, sistem sesi, kamera, takvimler veya Otomasyon çalışmayı bırakır. Bu, daha önce verdiğiniz izinleri yüklü sürüme yeniden bağlar. Asla yeni bir izin vermez. Tam Disk Erişimi gerektirir.",
                         button: "İzinleri onar",
                         repairedFormat: "Yeniden bağlanan izinler: %d. Kullanmak için RyzenStatus'u yeniden başlatın.",
                         nothingToRepair: "Onarılacak bir şey yok: verdiğiniz tüm izinler bu sürüm için geçerli.",
                         needsFullDiskAccess: "RyzenStatus'un izin listesini okumak için Tam Disk Erişimi'ne ihtiyacı var. Açın, uygulamayı yeniden başlatın ve tekrar deneyin.",
                         openFullDiskAccess: "Tam Disk Erişimi'ni aç",
                         failed: "İzinler onarılamadı.",
                         relaunch: "RyzenStatus'u yeniden başlat")
        case .ru:
            return .init(title: "Восстановить разрешения",
                         description: "После обновления macOS может оставить разрешение включённым, хотя оно уже не действует для новой версии: перестают работать микрофон, системный звук, камера, календари или автоматизация. Эта функция снова привязывает уже выданные вами разрешения к установленной версии. Она никогда не выдаёт новых. Нужен полный доступ к диску.",
                         button: "Восстановить разрешения",
                         repairedFormat: "Снова привязано разрешений: %d. Перезапустите RyzenStatus, чтобы они заработали.",
                         nothingToRepair: "Нечего восстанавливать: все выданные разрешения действуют для этой версии.",
                         needsFullDiskAccess: "RyzenStatus нужен полный доступ к диску, чтобы прочитать список разрешений. Включите его, перезапустите приложение и попробуйте снова.",
                         openFullDiskAccess: "Открыть «Полный доступ к диску»",
                         failed: "Не удалось восстановить разрешения.",
                         relaunch: "Перезапустить RyzenStatus")
        case .es:
            return .init(title: "Reparar permisos",
                         description: "Tras una actualización, macOS puede dejar un permiso activado aunque ya no valga para la versión nueva: el micrófono, el audio del sistema, la cámara, los calendarios o la Automatización dejan de funcionar. Esto vuelve a atar a la versión instalada los permisos que ya diste. Nunca concede nada nuevo. Necesita Acceso total al disco.",
                         button: "Reparar permisos",
                         repairedFormat: "Permisos atados de nuevo: %d. Reinicia RyzenStatus para usarlos.",
                         nothingToRepair: "Nada que reparar: todos los permisos que diste valen para esta versión.",
                         needsFullDiskAccess: "RyzenStatus necesita Acceso total al disco para leer la lista de permisos. Actívalo, reinicia la app y vuelve a intentarlo.",
                         openFullDiskAccess: "Abrir Acceso total al disco",
                         failed: "No se pudieron reparar los permisos.",
                         relaunch: "Reiniciar RyzenStatus")
        case .de:
            return .init(title: "Berechtigungen reparieren",
                         description: "Nach einem Update kann macOS eine Berechtigung eingeschaltet lassen, obwohl sie für die neue Version nicht mehr gilt: Mikrofon, Systemaudio, Kamera, Kalender oder Automation funktionieren dann nicht mehr. Dies bindet die bereits erteilten Berechtigungen wieder an die installierte Version. Es erteilt nie etwas Neues. Erfordert Festplattenvollzugriff.",
                         button: "Berechtigungen reparieren",
                         repairedFormat: "Neu gebundene Berechtigungen: %d. Starte RyzenStatus neu, um sie zu nutzen.",
                         nothingToRepair: "Nichts zu reparieren: Alle erteilten Berechtigungen gelten für diese Version.",
                         needsFullDiskAccess: "RyzenStatus braucht Festplattenvollzugriff, um die Berechtigungsliste zu lesen. Schalte ihn ein, starte die App neu und versuche es erneut.",
                         openFullDiskAccess: "Festplattenvollzugriff öffnen",
                         failed: "Die Berechtigungen konnten nicht repariert werden.",
                         relaunch: "RyzenStatus neu starten")
        case .fr:
            return .init(title: "Réparer les autorisations",
                         description: "Après une mise à jour, macOS peut laisser une autorisation activée alors qu'elle ne vaut plus pour la nouvelle version : le micro, l'audio du système, la caméra, les calendriers ou l'automatisation cessent de fonctionner. Ceci rattache à la version installée les autorisations que vous avez déjà données. Rien de nouveau n'est jamais accordé. Nécessite l'accès complet au disque.",
                         button: "Réparer les autorisations",
                         repairedFormat: "Autorisations rattachées : %d. Redémarrez RyzenStatus pour les utiliser.",
                         nothingToRepair: "Rien à réparer : toutes les autorisations données valent pour cette version.",
                         needsFullDiskAccess: "RyzenStatus a besoin de l'accès complet au disque pour lire la liste des autorisations. Activez-le, redémarrez l'app et réessayez.",
                         openFullDiskAccess: "Ouvrir Accès complet au disque",
                         failed: "Les autorisations n'ont pas pu être réparées.",
                         relaunch: "Redémarrer RyzenStatus")
        case .it:
            return .init(title: "Ripara permessi",
                         description: "Dopo un aggiornamento, macOS può lasciare attivo un permesso che non vale più per la nuova versione: microfono, audio di sistema, fotocamera, calendari o Automazione smettono di funzionare. Questa funzione ricollega alla versione installata i permessi che hai già concesso. Non concede mai nulla di nuovo. Richiede l'accesso completo al disco.",
                         button: "Ripara permessi",
                         repairedFormat: "Permessi ricollegati: %d. Riavvia RyzenStatus per usarli.",
                         nothingToRepair: "Niente da riparare: tutti i permessi concessi valgono per questa versione.",
                         needsFullDiskAccess: "RyzenStatus ha bisogno dell'accesso completo al disco per leggere l'elenco dei permessi. Attivalo, riavvia l'app e riprova.",
                         openFullDiskAccess: "Apri Accesso completo al disco",
                         failed: "Impossibile riparare i permessi.",
                         relaunch: "Riavvia RyzenStatus")
        case .ja:
            return .init(title: "権限を修復",
                         description: "アップデート後、macOS は権限をオンのまま残しても、新しいバージョンには適用しないことがあります。マイク、システムオーディオ、カメラ、カレンダー、オートメーションが動かなくなります。これは、すでに許可した権限をインストール済みのバージョンに結び直します。新しい権限を与えることはありません。フルディスクアクセスが必要です。",
                         button: "権限を修復",
                         repairedFormat: "結び直した権限: %d。使うには RyzenStatus を再起動してください。",
                         nothingToRepair: "修復するものはありません。許可した権限はすべてこのバージョンに適用されています。",
                         needsFullDiskAccess: "権限の一覧を読むには、RyzenStatus にフルディスクアクセスが必要です。オンにしてアプリを再起動し、もう一度お試しください。",
                         openFullDiskAccess: "フルディスクアクセスを開く",
                         failed: "権限を修復できませんでした。",
                         relaunch: "RyzenStatus を再起動")
        case .ko:
            return .init(title: "권한 복구",
                         description: "업데이트 후 macOS가 권한을 켜진 상태로 두면서도 새 버전에는 적용하지 않을 수 있습니다. 그러면 마이크, 시스템 오디오, 카메라, 캘린더 또는 자동화가 작동하지 않습니다. 이 기능은 이미 허용한 권한을 설치된 버전에 다시 연결합니다. 새 권한은 절대 부여하지 않습니다. 전체 디스크 접근 권한이 필요합니다.",
                         button: "권한 복구",
                         repairedFormat: "다시 연결된 권한: %d개. 사용하려면 RyzenStatus를 재시작하세요.",
                         nothingToRepair: "복구할 항목이 없습니다. 허용한 모든 권한이 이 버전에 적용됩니다.",
                         needsFullDiskAccess: "권한 목록을 읽으려면 RyzenStatus에 전체 디스크 접근 권한이 필요합니다. 켠 다음 앱을 재시작하고 다시 시도하세요.",
                         openFullDiskAccess: "전체 디스크 접근 권한 열기",
                         failed: "권한을 복구할 수 없습니다.",
                         relaunch: "RyzenStatus 재시작")
        case .zhHans:
            return .init(title: "修复权限",
                         description: "更新后，macOS 可能让某项权限保持开启，但它已不适用于新版本：麦克风、系统音频、摄像头、日历或自动化会停止工作。此功能会把你已授予的权限重新绑定到已安装的版本。它绝不会授予任何新权限。需要完全磁盘访问权限。",
                         button: "修复权限",
                         repairedFormat: "已重新绑定的权限：%d。重新启动 RyzenStatus 后生效。",
                         nothingToRepair: "无需修复：你授予的所有权限都适用于此版本。",
                         needsFullDiskAccess: "RyzenStatus 需要完全磁盘访问权限才能读取权限列表。请开启它，重新启动应用后再试。",
                         openFullDiskAccess: "打开完全磁盘访问权限",
                         failed: "无法修复权限。",
                         relaunch: "重新启动 RyzenStatus")
        case .zhTW:
            return .init(title: "修復權限",
                         description: "更新後，macOS 可能讓某項權限保持開啟，但它已不適用於新版本：麥克風、系統音訊、相機、行事曆或自動化會停止運作。此功能會把你已授予的權限重新綁定到已安裝的版本。它絕不會授予任何新權限。需要完整磁碟取用權限。",
                         button: "修復權限",
                         repairedFormat: "已重新綁定的權限：%d。重新啟動 RyzenStatus 後生效。",
                         nothingToRepair: "無需修復：你授予的所有權限都適用於此版本。",
                         needsFullDiskAccess: "RyzenStatus 需要完整磁碟取用權限才能讀取權限列表。請開啟它，重新啟動 App 後再試一次。",
                         openFullDiskAccess: "打開完整磁碟取用權限",
                         failed: "無法修復權限。",
                         relaunch: "重新啟動 RyzenStatus")
        case .zhHK:
            return .init(title: "修復權限",
                         description: "更新後，macOS 可能令某項權限保持開啟，但它已不適用於新版本：咪高峰、系統音訊、相機、日曆或自動化會停止運作。此功能會把你已授予的權限重新綁定到已安裝的版本。它絕不會授予任何新權限。需要完整磁碟取用權限。",
                         button: "修復權限",
                         repairedFormat: "已重新綁定的權限：%d。重新啟動 RyzenStatus 後生效。",
                         nothingToRepair: "無需修復：你授予的所有權限都適用於此版本。",
                         needsFullDiskAccess: "RyzenStatus 需要完整磁碟取用權限才能讀取權限列表。請開啟它，重新啟動 App 後再試一次。",
                         openFullDiskAccess: "打開完整磁碟取用權限",
                         failed: "無法修復權限。",
                         relaunch: "重新啟動 RyzenStatus")
        case .sk:
            return .init(title: "Opraviť povolenia",
                         description: "Po aktualizácii môže macOS nechať povolenie zapnuté, hoci už neplatí pre novú verziu: mikrofón, systémový zvuk, kamera, kalendáre alebo Automatizácia prestanú fungovať. Táto funkcia znova priviaže povolenia, ktoré ste už udelili, k nainštalovanej verzii. Nikdy neudelí nič nové. Vyžaduje úplný prístup k disku.",
                         button: "Opraviť povolenia",
                         repairedFormat: "Znova priviazané povolenia: %d. Reštartujte RyzenStatus, aby sa prejavili.",
                         nothingToRepair: "Nie je čo opraviť: všetky udelené povolenia platia pre túto verziu.",
                         needsFullDiskAccess: "RyzenStatus potrebuje úplný prístup k disku, aby mohol prečítať zoznam povolení. Zapnite ho, reštartujte aplikáciu a skúste to znova.",
                         openFullDiskAccess: "Otvoriť Úplný prístup k disku",
                         failed: "Povolenia sa nepodarilo opraviť.",
                         relaunch: "Reštartovať RyzenStatus")
        case .uk:
            return .init(title: "Відновити дозволи",
                         description: "Після оновлення macOS може залишити дозвіл увімкненим, хоча він уже не діє для нової версії: перестають працювати мікрофон, системний звук, камера, календарі або автоматизація. Ця функція знову прив'язує вже надані вами дозволи до встановленої версії. Вона ніколи не надає нових. Потрібен повний доступ до диска.",
                         button: "Відновити дозволи",
                         repairedFormat: "Знову прив'язано дозволів: %d. Перезапустіть RyzenStatus, щоб вони запрацювали.",
                         nothingToRepair: "Нічого відновлювати: усі надані дозволи діють для цієї версії.",
                         needsFullDiskAccess: "RyzenStatus потрібен повний доступ до диска, щоб прочитати список дозволів. Увімкніть його, перезапустіть програму й спробуйте знову.",
                         openFullDiskAccess: "Відкрити «Повний доступ до диска»",
                         failed: "Не вдалося відновити дозволи.",
                         relaunch: "Перезапустити RyzenStatus")
        }
    }
}
