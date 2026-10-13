// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

struct FeedbackStrings {
    let sectionTitle: String
    let sectionCaption: String
    let openButton: String
    let windowTitle: String
    let bugTitle: String
    let featureTitle: String
    let messageLabel: String
    let bugPlaceholder: String
    let featurePlaceholder: String
    let charactersFormat: String
    let includeDiagnostics: String
    let includeDiagnosticsCaption: String
    let whatSentTitle: String
    let whatSentBasic: String
    let whatSentDiagnostics: String
    let privacyNote: String
    let retentionNote: String
    let sendButton: String
    let sentTitle: String
    let sentCaption: String
    let unavailableError: String
    let genericError: String
    let done: String
    let commandBug: String
    let commandFeature: String
    let commandSubtitle: String
    let diagnosticsChannelLabel: String
}

extension FeatureStrings {
    static func feedback(_ language: AppLanguage) -> FeedbackStrings {
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

extension FeedbackStrings {
    static let enUS = FeedbackStrings(
        sectionTitle: "Feedback",
        sectionCaption: "Report a bug or suggest an idea as a public issue on the RyzenStatus GitHub repository.",
        openButton: "Send feedback",
        windowTitle: "Send feedback",
        bugTitle: "Bug",
        featureTitle: "Feature idea",
        messageLabel: "What would you like to share?",
        bugPlaceholder: "Tell me what happened and what you expected.",
        featurePlaceholder: "Describe the idea and how it would help.",
        charactersFormat: "%d of 2000 characters",
        includeDiagnostics: "Include technical details",
        includeDiagnosticsCaption: "Adds only the technical details shown below. It does not include logs.",
        whatSentTitle: "What the issue will contain",
        whatSentBasic: "Your chosen category and the text above.",
        whatSentDiagnostics: "The technical details listed below.",
        privacyNote: "Nothing is sent from the app. Your browser opens a prefilled GitHub issue that you can review, edit or discard. Submitting it requires your own GitHub account, and the issue is public.",
        retentionNote: "Public issues stay visible on GitHub until you or the maintainer delete them. Do not include personal data.",
        sendButton: "Continue on GitHub",
        sentTitle: "Issue opened in your browser",
        sentCaption: "Review it on GitHub and submit it from there. Until you do, nothing has been shared.",
        unavailableError: "Could not open the browser. Try again or visit the repository directly.",
        genericError: "Could not prepare the issue. Shorten the text and try again.",
        done: "Done",
        commandBug: "Report a bug",
        commandFeature: "Suggest a feature",
        commandSubtitle: "Send feedback",
        diagnosticsChannelLabel: "Update channel"
    )

    static let ptBR = FeedbackStrings(
        sectionTitle: "Feedback",
        sectionCaption: "Relate um bug ou sugira uma ideia como issue público no repositório do RyzenStatus no GitHub.",
        openButton: "Enviar feedback",
        windowTitle: "Enviar feedback",
        bugTitle: "Bug",
        featureTitle: "Ideia de recurso",
        messageLabel: "O que você gostaria de compartilhar?",
        bugPlaceholder: "Conte o que aconteceu e o que você esperava.",
        featurePlaceholder: "Descreva a ideia e como ela ajudaria.",
        charactersFormat: "%d de 2000 caracteres",
        includeDiagnostics: "Incluir dados técnicos",
        includeDiagnosticsCaption: "Adiciona somente os dados técnicos mostrados abaixo. Não inclui logs.",
        whatSentTitle: "O que o issue vai conter",
        whatSentBasic: "A categoria escolhida e o texto acima.",
        whatSentDiagnostics: "Os dados técnicos listados abaixo.",
        privacyNote: "Nada é enviado pelo app. O navegador abre um issue do GitHub já preenchido, que você pode revisar, editar ou descartar. Para publicá-lo é preciso ter sua própria conta no GitHub, e o issue é público.",
        retentionNote: "Issues públicos ficam visíveis no GitHub até que você ou o mantenedor os excluam. Não inclua dados pessoais.",
        sendButton: "Continuar no GitHub",
        sentTitle: "Issue aberto no navegador",
        sentCaption: "Revise no GitHub e publique por lá. Até lá, nada foi compartilhado.",
        unavailableError: "Não foi possível abrir o navegador. Tente novamente ou acesse o repositório diretamente.",
        genericError: "Não foi possível preparar o issue. Encurte o texto e tente novamente.",
        done: "Concluído",
        commandBug: "Relatar um bug",
        commandFeature: "Sugerir um recurso",
        commandSubtitle: "Enviar feedback",
        diagnosticsChannelLabel: "Canal de atualização"
    )

    static let tr = FeedbackStrings(
        sectionTitle: "Geri bildirim",
        sectionCaption: "Bir hatayı bildirin veya bir fikir önerin; GitHub'daki RyzenStatus deposunda herkese açık bir issue olarak açılır.",
        openButton: "Geri bildirim gönder",
        windowTitle: "Geri bildirim gönder",
        bugTitle: "Hata",
        featureTitle: "Özellik fikri",
        messageLabel: "Ne paylaşmak istersiniz?",
        bugPlaceholder: "Ne olduğunu ve ne beklediğinizi anlatın.",
        featurePlaceholder: "Fikri ve nasıl yardımcı olacağını açıklayın.",
        charactersFormat: "2000 karakterden %d",
        includeDiagnostics: "Teknik ayrıntıları ekle",
        includeDiagnosticsCaption: "Yalnızca aşağıda gösterilen teknik ayrıntıları ekler. Günlükler eklenmez.",
        whatSentTitle: "Issue'da neler olacak",
        whatSentBasic: "Seçtiğiniz kategori ve yukarıdaki metin.",
        whatSentDiagnostics: "Aşağıda listelenen teknik ayrıntılar.",
        privacyNote: "Uygulama hiçbir şey göndermez. Tarayıcınız, inceleyip düzenleyebileceğiniz veya vazgeçebileceğiniz önceden doldurulmuş bir GitHub issue'su açar. Göndermek için kendi GitHub hesabınız gerekir ve issue herkese açıktır.",
        retentionNote: "Herkese açık issue'lar siz veya geliştirici silene kadar GitHub'da görünür kalır. Kişisel veri eklemeyin.",
        sendButton: "GitHub'da devam et",
        sentTitle: "Issue tarayıcınızda açıldı",
        sentCaption: "GitHub'da gözden geçirip oradan gönderin. Siz gönderene kadar hiçbir şey paylaşılmaz.",
        unavailableError: "Tarayıcı açılamadı. Tekrar deneyin veya depoyu doğrudan ziyaret edin.",
        genericError: "Issue hazırlanamadı. Metni kısaltıp tekrar deneyin.",
        done: "Bitti",
        commandBug: "Hata bildir",
        commandFeature: "Özellik öner",
        commandSubtitle: "Geri bildirim gönder",
        diagnosticsChannelLabel: "Güncelleme kanalı"
    )

    static let ru = FeedbackStrings(
        sectionTitle: "Обратная связь",
        sectionCaption: "Сообщите об ошибке или предложите идею — она станет публичным issue в репозитории RyzenStatus на GitHub.",
        openButton: "Отправить отзыв",
        windowTitle: "Отправить отзыв",
        bugTitle: "Ошибка",
        featureTitle: "Идея функции",
        messageLabel: "Чем вы хотите поделиться?",
        bugPlaceholder: "Опишите, что произошло и чего вы ожидали.",
        featurePlaceholder: "Опишите идею и чем она поможет.",
        charactersFormat: "%d из 2000 символов",
        includeDiagnostics: "Добавить технические данные",
        includeDiagnosticsCaption: "Добавляет только технические данные, показанные ниже. Журналы не добавляются.",
        whatSentTitle: "Что будет в issue",
        whatSentBasic: "Выбранная категория и текст выше.",
        whatSentDiagnostics: "Технические данные, перечисленные ниже.",
        privacyNote: "Приложение ничего не отправляет. Браузер откроет заполненный issue на GitHub, который можно проверить, изменить или отменить. Для публикации нужна ваша собственная учётная запись GitHub, и issue будет публичным.",
        retentionNote: "Публичные issue остаются видимыми на GitHub, пока вы или разработчик их не удалите. Не указывайте личные данные.",
        sendButton: "Продолжить на GitHub",
        sentTitle: "Issue открыт в браузере",
        sentCaption: "Проверьте его на GitHub и опубликуйте оттуда. До этого ничего не передаётся.",
        unavailableError: "Не удалось открыть браузер. Попробуйте ещё раз или откройте репозиторий напрямую.",
        genericError: "Не удалось подготовить issue. Сократите текст и попробуйте ещё раз.",
        done: "Готово",
        commandBug: "Сообщить об ошибке",
        commandFeature: "Предложить функцию",
        commandSubtitle: "Отправить отзыв",
        diagnosticsChannelLabel: "Канал обновлений"
    )

    static let es = FeedbackStrings(
        sectionTitle: "Comentarios",
        sectionCaption: "Informa de un error o sugiere una idea como issue público en el repositorio de RyzenStatus en GitHub.",
        openButton: "Enviar comentarios",
        windowTitle: "Enviar comentarios",
        bugTitle: "Error",
        featureTitle: "Idea de función",
        messageLabel: "¿Qué quieres compartir?",
        bugPlaceholder: "Cuenta qué ocurrió y qué esperabas.",
        featurePlaceholder: "Describe la idea y cómo ayudaría.",
        charactersFormat: "%d de 2000 caracteres",
        includeDiagnostics: "Incluir datos técnicos",
        includeDiagnosticsCaption: "Añade solo los datos técnicos mostrados abajo. No incluye registros.",
        whatSentTitle: "Qué contendrá el issue",
        whatSentBasic: "La categoría elegida y el texto anterior.",
        whatSentDiagnostics: "Los datos técnicos indicados abajo.",
        privacyNote: "La app no envía nada. Tu navegador abre un issue de GitHub ya rellenado que puedes revisar, editar o descartar. Para publicarlo necesitas tu propia cuenta de GitHub, y el issue es público.",
        retentionNote: "Los issues públicos siguen visibles en GitHub hasta que tú o el responsable los eliminen. No incluyas datos personales.",
        sendButton: "Continuar en GitHub",
        sentTitle: "Issue abierto en tu navegador",
        sentCaption: "Revísalo en GitHub y publícalo desde allí. Hasta entonces no se ha compartido nada.",
        unavailableError: "No se pudo abrir el navegador. Inténtalo de nuevo o visita el repositorio directamente.",
        genericError: "No se pudo preparar el issue. Acorta el texto e inténtalo de nuevo.",
        done: "Listo",
        commandBug: "Informar de un error",
        commandFeature: "Sugerir una función",
        commandSubtitle: "Enviar comentarios",
        diagnosticsChannelLabel: "Canal de actualización"
    )

    static let sk = FeedbackStrings(
        sectionTitle: "Spätná väzba",
        sectionCaption: "Nahláste chybu alebo navrhnite nápad ako verejný issue v repozitári RyzenStatus na GitHube.",
        openButton: "Poslať spätnú väzbu",
        windowTitle: "Poslať spätnú väzbu",
        bugTitle: "Chyba",
        featureTitle: "Nápad na funkciu",
        messageLabel: "Čo by ste chceli zdieľať?",
        bugPlaceholder: "Napíšte, čo sa stalo a čo ste očakávali.",
        featurePlaceholder: "Opíšte nápad a ako by pomohol.",
        charactersFormat: "%d z 2000 znakov",
        includeDiagnostics: "Zahrnúť technické detaily",
        includeDiagnosticsCaption: "Pridá iba technické detaily zobrazené nižšie. Neobsahuje záznamy.",
        whatSentTitle: "Čo bude issue obsahovať",
        whatSentBasic: "Vybraná kategória a text vyššie.",
        whatSentDiagnostics: "Technické detaily uvedené nižšie.",
        privacyNote: "Aplikácia nič neodosiela. Prehliadač otvorí vopred vyplnený issue na GitHube, ktorý môžete skontrolovať, upraviť alebo zahodiť. Na odoslanie potrebujete vlastný účet GitHub a issue je verejný.",
        retentionNote: "Verejné issues zostávajú na GitHube viditeľné, kým ich vy alebo správca neodstránite. Neuvádzajte osobné údaje.",
        sendButton: "Pokračovať na GitHube",
        sentTitle: "Issue sa otvoril v prehliadači",
        sentCaption: "Skontrolujte ho na GitHube a odošlite odtiaľ. Dovtedy sa nič nezdieľa.",
        unavailableError: "Prehliadač sa nepodarilo otvoriť. Skúste to znova alebo otvorte repozitár priamo.",
        genericError: "Issue sa nepodarilo pripraviť. Skráťte text a skúste to znova.",
        done: "Hotovo",
        commandBug: "Nahlásiť chybu",
        commandFeature: "Navrhnúť funkciu",
        commandSubtitle: "Poslať spätnú väzbu",
        diagnosticsChannelLabel: "Kanál aktualizácií"
    )

    static let de = FeedbackStrings(
        sectionTitle: "Feedback",
        sectionCaption: "Melde einen Fehler oder schlage eine Idee vor – als öffentliches Issue im RyzenStatus-Repository auf GitHub.",
        openButton: "Feedback senden",
        windowTitle: "Feedback senden",
        bugTitle: "Fehler",
        featureTitle: "Funktionsidee",
        messageLabel: "Was möchtest du mitteilen?",
        bugPlaceholder: "Beschreibe, was passiert ist und was du erwartet hast.",
        featurePlaceholder: "Beschreibe die Idee und wie sie helfen würde.",
        charactersFormat: "%d von 2000 Zeichen",
        includeDiagnostics: "Technische Daten mitsenden",
        includeDiagnosticsCaption: "Fügt nur die unten gezeigten technischen Daten hinzu. Keine Protokolle.",
        whatSentTitle: "Was das Issue enthält",
        whatSentBasic: "Die gewählte Kategorie und der Text oben.",
        whatSentDiagnostics: "Die unten aufgeführten technischen Daten.",
        privacyNote: "Die App sendet nichts. Dein Browser öffnet ein vorausgefülltes GitHub-Issue, das du prüfen, bearbeiten oder verwerfen kannst. Zum Absenden brauchst du ein eigenes GitHub-Konto, und das Issue ist öffentlich.",
        retentionNote: "Öffentliche Issues bleiben auf GitHub sichtbar, bis du oder der Maintainer sie löschen. Gib keine persönlichen Daten an.",
        sendButton: "Auf GitHub fortfahren",
        sentTitle: "Issue im Browser geöffnet",
        sentCaption: "Prüfe es auf GitHub und sende es dort ab. Bis dahin wurde nichts geteilt.",
        unavailableError: "Der Browser konnte nicht geöffnet werden. Versuche es erneut oder öffne das Repository direkt.",
        genericError: "Das Issue konnte nicht vorbereitet werden. Kürze den Text und versuche es erneut.",
        done: "Fertig",
        commandBug: "Fehler melden",
        commandFeature: "Funktion vorschlagen",
        commandSubtitle: "Feedback senden",
        diagnosticsChannelLabel: "Update-Kanal"
    )

    static let fr = FeedbackStrings(
        sectionTitle: "Avis",
        sectionCaption: "Signalez un bug ou proposez une idée sous forme d’issue publique dans le dépôt RyzenStatus sur GitHub.",
        openButton: "Envoyer un avis",
        windowTitle: "Envoyer un avis",
        bugTitle: "Bug",
        featureTitle: "Idée de fonction",
        messageLabel: "Que souhaitez-vous partager\u{00A0}?",
        bugPlaceholder: "Décrivez ce qui s’est passé et ce que vous attendiez.",
        featurePlaceholder: "Décrivez l’idée et son utilité.",
        charactersFormat: "%d caractères sur 2000",
        includeDiagnostics: "Inclure les données techniques",
        includeDiagnosticsCaption: "Ajoute uniquement les données techniques affichées ci-dessous. Aucun journal.",
        whatSentTitle: "Contenu de l’issue",
        whatSentBasic: "La catégorie choisie et le texte ci-dessus.",
        whatSentDiagnostics: "Les données techniques listées ci-dessous.",
        privacyNote: "L’app n’envoie rien. Votre navigateur ouvre une issue GitHub préremplie que vous pouvez relire, modifier ou abandonner. Pour la publier, il faut votre propre compte GitHub, et l’issue est publique.",
        retentionNote: "Les issues publiques restent visibles sur GitHub jusqu’à ce que vous ou le mainteneur les supprimiez. N’incluez pas de données personnelles.",
        sendButton: "Continuer sur GitHub",
        sentTitle: "Issue ouverte dans votre navigateur",
        sentCaption: "Relisez-la sur GitHub et publiez-la depuis là-bas. D’ici là, rien n’a été partagé.",
        unavailableError: "Impossible d’ouvrir le navigateur. Réessayez ou ouvrez directement le dépôt.",
        genericError: "Impossible de préparer l’issue. Raccourcissez le texte et réessayez.",
        done: "Terminé",
        commandBug: "Signaler un bug",
        commandFeature: "Suggérer une fonction",
        commandSubtitle: "Envoyer un avis",
        diagnosticsChannelLabel: "Canal de mise à jour"
    )

    static let it = FeedbackStrings(
        sectionTitle: "Feedback",
        sectionCaption: "Segnala un bug o proponi un’idea come issue pubblica nel repository RyzenStatus su GitHub.",
        openButton: "Invia feedback",
        windowTitle: "Invia feedback",
        bugTitle: "Bug",
        featureTitle: "Idea per una funzione",
        messageLabel: "Cosa vuoi condividere?",
        bugPlaceholder: "Descrivi cosa è successo e cosa ti aspettavi.",
        featurePlaceholder: "Descrivi l’idea e come potrebbe aiutare.",
        charactersFormat: "%d di 2000 caratteri",
        includeDiagnostics: "Includi dati tecnici",
        includeDiagnosticsCaption: "Aggiunge solo i dati tecnici mostrati sotto. Non include registri.",
        whatSentTitle: "Cosa conterrà la issue",
        whatSentBasic: "La categoria scelta e il testo qui sopra.",
        whatSentDiagnostics: "I dati tecnici elencati qui sotto.",
        privacyNote: "L’app non invia nulla. Il browser apre una issue di GitHub già compilata che puoi rivedere, modificare o scartare. Per pubblicarla serve il tuo account GitHub e la issue è pubblica.",
        retentionNote: "Le issue pubbliche restano visibili su GitHub finché tu o il manutentore non le eliminate. Non includere dati personali.",
        sendButton: "Continua su GitHub",
        sentTitle: "Issue aperta nel browser",
        sentCaption: "Rivedila su GitHub e pubblicala da lì. Fino ad allora non è stato condiviso nulla.",
        unavailableError: "Impossibile aprire il browser. Riprova o apri direttamente il repository.",
        genericError: "Impossibile preparare la issue. Accorcia il testo e riprova.",
        done: "Fine",
        commandBug: "Segnala un bug",
        commandFeature: "Suggerisci una funzione",
        commandSubtitle: "Invia feedback",
        diagnosticsChannelLabel: "Canale di aggiornamento"
    )

    static let ja = FeedbackStrings(
        sectionTitle: "フィードバック",
        sectionCaption: "不具合の報告やアイデアの提案を、GitHub の RyzenStatus リポジトリに公開 Issue として作成します。",
        openButton: "フィードバックを送信",
        windowTitle: "フィードバックを送信",
        bugTitle: "不具合",
        featureTitle: "機能のアイデア",
        messageLabel: "共有したい内容を入力してください",
        bugPlaceholder: "何が起き、どうなることを期待していたかを説明してください。",
        featurePlaceholder: "アイデアと、どのように役立つかを説明してください。",
        charactersFormat: "2000文字中%d文字",
        includeDiagnostics: "技術情報を含める",
        includeDiagnosticsCaption: "下に表示される技術情報だけを追加します。ログは含みません。",
        whatSentTitle: "Issue に含まれる内容",
        whatSentBasic: "選択した種類と上の文章。",
        whatSentDiagnostics: "下に表示される技術情報。",
        privacyNote: "アプリからは何も送信されません。ブラウザで入力済みの GitHub Issue が開き、確認・編集・破棄できます。投稿にはご自身の GitHub アカウントが必要で、Issue は公開されます。",
        retentionNote: "公開 Issue は、あなたまたはメンテナーが削除するまで GitHub に表示されます。個人情報は含めないでください。",
        sendButton: "GitHub で続ける",
        sentTitle: "ブラウザで Issue を開きました",
        sentCaption: "GitHub で内容を確認し、そこから投稿してください。投稿するまで何も共有されません。",
        unavailableError: "ブラウザを開けませんでした。もう一度試すか、リポジトリを直接開いてください。",
        genericError: "Issue を準備できませんでした。テキストを短くしてもう一度お試しください。",
        done: "完了",
        commandBug: "不具合を報告",
        commandFeature: "機能を提案",
        commandSubtitle: "フィードバックを送信",
        diagnosticsChannelLabel: "アップデートチャンネル"
    )

    static let ko = FeedbackStrings(
        sectionTitle: "피드백",
        sectionCaption: "버그를 신고하거나 아이디어를 제안하면 GitHub의 RyzenStatus 저장소에 공개 이슈로 작성됩니다.",
        openButton: "피드백 보내기",
        windowTitle: "피드백 보내기",
        bugTitle: "버그",
        featureTitle: "기능 아이디어",
        messageLabel: "무엇을 공유하시겠습니까?",
        bugPlaceholder: "무슨 일이 있었고 무엇을 기대했는지 알려 주세요.",
        featurePlaceholder: "아이디어와 도움이 되는 이유를 설명해 주세요.",
        charactersFormat: "2000자 중 %d자",
        includeDiagnostics: "기술 정보 포함",
        includeDiagnosticsCaption: "아래에 표시된 기술 정보만 추가합니다. 로그는 포함하지 않습니다.",
        whatSentTitle: "이슈에 포함될 내용",
        whatSentBasic: "선택한 종류와 위의 글.",
        whatSentDiagnostics: "아래에 표시된 기술 정보.",
        privacyNote: "앱에서는 아무것도 전송하지 않습니다. 브라우저에서 미리 채워진 GitHub 이슈가 열리며, 검토하거나 수정하거나 취소할 수 있습니다. 게시하려면 본인의 GitHub 계정이 필요하며 이슈는 공개됩니다.",
        retentionNote: "공개 이슈는 본인 또는 관리자가 삭제할 때까지 GitHub에 표시됩니다. 개인 정보는 포함하지 마세요.",
        sendButton: "GitHub에서 계속",
        sentTitle: "브라우저에서 이슈를 열었습니다",
        sentCaption: "GitHub에서 확인한 뒤 그곳에서 게시하세요. 게시하기 전에는 아무것도 공유되지 않습니다.",
        unavailableError: "브라우저를 열 수 없습니다. 다시 시도하거나 저장소를 직접 방문하세요.",
        genericError: "이슈를 준비할 수 없습니다. 텍스트를 줄인 뒤 다시 시도하세요.",
        done: "완료",
        commandBug: "버그 신고",
        commandFeature: "기능 제안",
        commandSubtitle: "피드백 보내기",
        diagnosticsChannelLabel: "업데이트 채널"
    )

    static let zhHans = FeedbackStrings(
        sectionTitle: "反馈",
        sectionCaption: "报告错误或提出想法，将作为公开 Issue 发布在 GitHub 上的 RyzenStatus 仓库中。",
        openButton: "发送反馈",
        windowTitle: "发送反馈",
        bugTitle: "错误",
        featureTitle: "功能建议",
        messageLabel: "你想分享什么？",
        bugPlaceholder: "说明发生了什么以及你原本的预期。",
        featurePlaceholder: "说明你的想法以及它能带来什么帮助。",
        charactersFormat: "已输入 %d/2000 个字符",
        includeDiagnostics: "包含技术信息",
        includeDiagnosticsCaption: "仅添加下方显示的技术信息。不包含日志。",
        whatSentTitle: "Issue 将包含的内容",
        whatSentBasic: "所选类别和上方文字。",
        whatSentDiagnostics: "下方列出的技术信息。",
        privacyNote: "应用不会发送任何内容。浏览器会打开一个已预填的 GitHub Issue，你可以检查、编辑或放弃。提交需要你自己的 GitHub 账户，且 Issue 是公开的。",
        retentionNote: "公开 Issue 会一直显示在 GitHub 上，直到你或维护者将其删除。请勿包含个人数据。",
        sendButton: "在 GitHub 上继续",
        sentTitle: "已在浏览器中打开 Issue",
        sentCaption: "请在 GitHub 上检查并从那里提交。在此之前不会共享任何内容。",
        unavailableError: "无法打开浏览器。请重试，或直接访问仓库。",
        genericError: "无法准备 Issue。请缩短文本后重试。",
        done: "完成",
        commandBug: "报告错误",
        commandFeature: "建议功能",
        commandSubtitle: "发送反馈",
        diagnosticsChannelLabel: "更新渠道"
    )

    static let zhTW = FeedbackStrings(
        sectionTitle: "意見回饋",
        sectionCaption: "回報錯誤或提出想法，會以公開 Issue 的形式發佈在 GitHub 上的 RyzenStatus 儲存庫。",
        openButton: "傳送意見",
        windowTitle: "傳送意見",
        bugTitle: "錯誤",
        featureTitle: "功能建議",
        messageLabel: "你想分享什麼？",
        bugPlaceholder: "說明發生了什麼以及你原本的預期。",
        featurePlaceholder: "說明你的想法以及它能帶來什麼幫助。",
        charactersFormat: "已輸入 %d/2000 個字元",
        includeDiagnostics: "包含技術資訊",
        includeDiagnosticsCaption: "只加入下方顯示的技術資料。不包含記錄。",
        whatSentTitle: "Issue 將包含的內容",
        whatSentBasic: "所選類別與上方文字。",
        whatSentDiagnostics: "下方列出的技術資訊。",
        privacyNote: "App 不會傳送任何內容。瀏覽器會開啟已預先填寫的 GitHub Issue，你可以檢查、編輯或捨棄。提交需要你自己的 GitHub 帳號，且 Issue 是公開的。",
        retentionNote: "公開 Issue 會持續顯示在 GitHub 上，直到你或維護者將其刪除。請勿包含個人資料。",
        sendButton: "在 GitHub 上繼續",
        sentTitle: "已在瀏覽器中開啟 Issue",
        sentCaption: "請在 GitHub 上檢查並從那裡提交。在此之前不會分享任何內容。",
        unavailableError: "無法開啟瀏覽器。請再試一次，或直接前往儲存庫。",
        genericError: "無法準備 Issue。請縮短文字後再試一次。",
        done: "完成",
        commandBug: "回報錯誤",
        commandFeature: "建議功能",
        commandSubtitle: "傳送意見",
        diagnosticsChannelLabel: "更新頻道"
    )

    static let zhHK = FeedbackStrings(
        sectionTitle: "意見回饋",
        sectionCaption: "回報錯誤或提出意見，會以公開 Issue 形式發佈到 GitHub 上的 RyzenStatus 儲存庫。",
        openButton: "傳送意見",
        windowTitle: "傳送意見",
        bugTitle: "錯誤",
        featureTitle: "功能建議",
        messageLabel: "你想分享甚麼？",
        bugPlaceholder: "說明發生了甚麼以及你原本的預期。",
        featurePlaceholder: "說明你的想法以及它能帶來甚麼幫助。",
        charactersFormat: "已輸入 %d/2000 個字元",
        includeDiagnostics: "包含技術資料",
        includeDiagnosticsCaption: "只加入下方顯示的技術資料。不包含記錄。",
        whatSentTitle: "Issue 會包含的內容",
        whatSentBasic: "所選類別與上方文字。",
        whatSentDiagnostics: "下方列出的技術資料。",
        privacyNote: "App 不會傳送任何內容。瀏覽器會開啟已預先填寫的 GitHub Issue，你可以檢查、編輯或放棄。提交需要你自己的 GitHub 帳戶，而且 Issue 是公開的。",
        retentionNote: "公開 Issue 會一直顯示在 GitHub 上，直至你或維護者將其刪除。請勿包含個人資料。",
        sendButton: "在 GitHub 繼續",
        sentTitle: "已在瀏覽器開啟 Issue",
        sentCaption: "請在 GitHub 檢查並從那裡提交。在此之前不會分享任何內容。",
        unavailableError: "無法開啟瀏覽器。請再試一次，或直接前往儲存庫。",
        genericError: "無法準備 Issue。請縮短文字後再試一次。",
        done: "完成",
        commandBug: "報告錯誤",
        commandFeature: "建議功能",
        commandSubtitle: "傳送意見",
        diagnosticsChannelLabel: "更新頻道"
    )
    static let uk = FeedbackStrings(
        sectionTitle: "Відгук",
        sectionCaption: "Повідомте про помилку або запропонуйте ідею — вона стане публічним issue в репозиторії RyzenStatus на GitHub.",
        openButton: "Надіслати відгук",
        windowTitle: "Надіслати відгук",
        bugTitle: "Помилка",
        featureTitle: "Ідея функції",
        messageLabel: "Чим би ви хотіли поділитися?",
        bugPlaceholder: "Розкажіть, що сталося та що ви очікували.",
        featurePlaceholder: "Опишіть ідею та як вона допоможе.",
        charactersFormat: "%d з 2000 символів",
        includeDiagnostics: "Включити технічні деталі",
        includeDiagnosticsCaption: "Додає лише технічні деталі, показані нижче. Вони не включають журнали.",
        whatSentTitle: "Що міститиме issue",
        whatSentBasic: "Ваша обрана категорія та текст вище.",
        whatSentDiagnostics: "Технічні деталі, перелічені нижче.",
        privacyNote: "Застосунок нічого не надсилає. Браузер відкриє заповнений issue на GitHub, який можна переглянути, змінити або скасувати. Для публікації потрібен ваш власний обліковий запис GitHub, і issue буде публічним.",
        retentionNote: "Публічні issue залишаються видимими на GitHub, доки ви або розробник їх не видалите. Не додавайте особисті дані.",
        sendButton: "Продовжити на GitHub",
        sentTitle: "Issue відкрито в браузері",
        sentCaption: "Перегляньте його на GitHub і опублікуйте звідти. До того нічого не передається.",
        unavailableError: "Не вдалося відкрити браузер. Спробуйте ще раз або відкрийте репозиторій напряму.",
        genericError: "Не вдалося підготувати issue. Скоротіть текст і спробуйте ще раз.",
        done: "Готово",
        commandBug: "Повідомити про помилку",
        commandFeature: "Запропонувати функцію",
        commandSubtitle: "Надіслати відгук",
        diagnosticsChannelLabel: "Канал оновлення"
    )
}
