// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

struct NotchGestureStrings {
    let title: String
    let description: String
    let hint: String
}

extension FeatureStrings {
    static func notchGestures(_ language: AppLanguage) -> NotchGestureStrings {
        switch language {
        case .enUS: return NotchGestureStrings(
            title: "Dynamic Island Gestures",
            description: "Open and close the Dynamic Island with scrolling, and swipe to change tracks.",
            hint: "Scroll down to open. Scroll up over the top row to close. Swipe left or right over the music to change tracks. Swipe sideways over another activity to switch between activities. Scroll up over a notice to dismiss it. Lists keep their own scrolling.")
        case .ptBR: return NotchGestureStrings(
            title: "Gestos do Dynamic Island",
            description: "Abra e feche o Dynamic Island com a rolagem e deslize para trocar de música.",
            hint: "Role para baixo para abrir. Role para cima sobre a faixa superior para fechar. Deslize para os lados sobre a música para trocar de faixa. Deslize para os lados sobre outra atividade para alternar entre atividades. Role para cima sobre um aviso para dispensá-lo. As listas mantêm a própria rolagem.")
        case .es: return NotchGestureStrings(
            title: "Gestos del Dynamic Island",
            description: "Abre y cierra el Dynamic Island al desplazarte y desliza para cambiar de canción.",
            hint: "Desplázate hacia abajo para abrir. Hacia arriba sobre la fila superior para cerrar. Desliza a los lados sobre la música para cambiar de pista. Desliza a los lados sobre otra actividad para pasar de una a otra. Desplázate hacia arriba sobre un aviso para descartarlo. Las listas conservan su desplazamiento.")
        case .sk: return NotchGestureStrings(
            title: "Gestá Dynamic Island",
            description: "Otvorte a zatvorte Dynamic Island posúvaním a potiahnutím zmeňte skladbu.",
            hint: "Posunutím nadol otvoríte. Posunutím nahor nad horným riadkom zatvoríte. Potiahnutím doľava alebo doprava nad hudbou zmeníte skladbu. Potiahnutím do strán nad inou aktivitou prepínate medzi aktivitami. Posunutím nahor nad upozornením ho zavriete. Zoznamy si zachovávajú vlastné posúvanie.")
        case .de: return NotchGestureStrings(
            title: "Dynamic Island-Gesten",
            description: "Öffne und schließe den Dynamic Island durch Scrollen und wechsle Titel durch Wischen.",
            hint: "Scrolle zum Öffnen nach unten und über der oberen Zeile zum Schließen nach oben. Wische über der Musik seitlich, um den Titel zu wechseln. Wische über einer anderen Aktivität seitlich, um zwischen Aktivitäten zu wechseln. Scrolle über einem Hinweis nach oben, um ihn zu schließen. Listen behalten ihr Scrollverhalten.")
        case .fr: return NotchGestureStrings(
            title: "Gestes du Dynamic Island",
            description: "Ouvrez et fermez le Dynamic Island par défilement et balayez pour changer de morceau.",
            hint: "Faites défiler vers le bas pour ouvrir, vers le haut sur la rangée supérieure pour fermer. Balayez latéralement sur la musique pour changer de morceau. Balayez latéralement sur une autre activité pour passer de l’une à l’autre. Faites défiler vers le haut sur une notification pour la fermer. Les listes gardent leur défilement.")
        case .it: return NotchGestureStrings(
            title: "Gesti del Dynamic Island",
            description: "Apri e chiudi il Dynamic Island scorrendo e cambia brano con un gesto laterale.",
            hint: "Scorri verso il basso per aprire e verso l’alto sulla riga superiore per chiudere. Scorri lateralmente sulla musica per cambiare brano. Scorri lateralmente su un’altra attività per passare da un’attività all’altra. Scorri verso l’alto su un avviso per chiuderlo. Le liste mantengono il loro scorrimento.")
        case .ru: return NotchGestureStrings(
            title: "Жесты для выреза",
            description: "Открывайте и закрывайте панель прокруткой, меняйте треки смахиванием.",
            hint: "Прокрутите вниз для открытия и вверх над верхней строкой для закрытия. Смахните влево или вправо над музыкой для смены трека. Смахните в сторону над другой активностью, чтобы переключать активности. Прокрутите вверх над уведомлением, чтобы закрыть его. Прокрутка списков работает как обычно.")
        case .tr: return NotchGestureStrings(
            title: "Çentik Hareketleri",
            description: "Kaydırarak çentiği açıp kapatın ve parçaları değiştirin.",
            hint: "Açmak için aşağı kaydırın. Kapatmak için üst satırda yukarı kaydırın. Parçayı değiştirmek için müziğin üzerinde yana kaydırın. Etkinlikler arasında geçiş yapmak için başka bir etkinliğin üzerinde yana kaydırın. Bir bildirimi kapatmak için üzerinde yukarı kaydırın. Listeler kendi kaydırma davranışını korur.")
        case .ja: return NotchGestureStrings(
            title: "Dynamic Islandのジェスチャ",
            description: "スクロールでDynamic Islandを開閉し、スワイプで曲を切り替えます。",
            hint: "下にスクロールすると開き、上部の行で上にスクロールすると閉じます。音楽の上で左右にスワイプすると曲が切り替わります。ほかのアクティビティの上で左右にスワイプするとアクティビティが切り替わります。通知の上で上にスクロールすると閉じます。リストは通常どおりスクロールできます。")
        case .ko: return NotchGestureStrings(
            title: "Dynamic Island 제스처",
            description: "스크롤로 Dynamic Island를 열고 닫고, 옆으로 쓸어 곡을 바꾸세요.",
            hint: "아래로 스크롤하면 열립니다. 상단 줄에서 위로 스크롤하면 닫힙니다. 음악 위에서 좌우로 쓸면 곡이 바뀝니다. 다른 활동 위에서 좌우로 쓸면 활동이 전환됩니다. 알림 위에서 위로 스크롤하면 알림이 닫힙니다. 목록은 기존처럼 스크롤됩니다.")
        case .zhHans: return NotchGestureStrings(
            title: "Dynamic Island手势",
            description: "滚动以打开或关闭Dynamic Island，左右轻扫以切换歌曲。",
            hint: "向下滚动以打开，在顶部栏向上滚动以关闭。在音乐上左右轻扫以切换歌曲。在其他活动上左右轻扫以切换活动。在通知上向上滚动以关闭通知。列表保持原有滚动方式。")
        case .zhTW: return NotchGestureStrings(
            title: "Dynamic Island手勢",
            description: "捲動以打開或關閉Dynamic Island，左右滑動以切換歌曲。",
            hint: "向下捲動以打開，在頂部列向上捲動以關閉。在音樂上左右滑動以切換歌曲。在其他活動上左右滑動以切換活動。在通知上向上捲動以關閉通知。列表保留原有的捲動方式。")
        case .zhHK: return NotchGestureStrings(
            title: "Dynamic Island手勢",
            description: "捲動以開啟或關閉Dynamic Island，左右滑動以切換歌曲。",
            hint: "向下捲動以開啟，在頂部列向上捲動以關閉。在音樂上左右滑動以切換歌曲。在其他活動上左右滑動以切換活動。在通知上向上捲動以關閉通知。列表保留原有的捲動方式。")
        case .uk: return NotchGestureStrings(
            title: "Жести Dynamic Island",
            description: "Відкривайте та закривайте Dynamic Island прокручуванням і змінюйте треки змахуванням.",
            hint: "Прокрутіть униз, щоб відкрити, і вгору над верхнім рядком, щоб закрити. Змахніть ліворуч або праворуч над музикою, щоб змінити трек. Змахніть убік над іншою активністю, щоб перемикати активності. Прокрутіть угору над сповіщенням, щоб закрити його. Списки прокручуються як зазвичай.")
        }
    }
}
