// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

struct FanControlFeatureStrings {
    let title: String
    let fansHeader: String
    let fanHeaderFormat: String
    let speedLabel: String
    let modeLabel: String
    let autoMode: String
    let manualMode: String
    let customCurveMode: String
    let targetPwmLabel: String
    let maxSpeedButton: String
    let allAutoButton: String
    let maxSpeedConfirmationTitle: String
    let maxSpeedConfirmationMessage: String
    let confirmButton: String
    let cancelButton: String
    let fanCurvesSection: String
    let curveNameLabel: String
    let sourceSensorLabel: String
    let hysteresisLabel: String
    let rampRateLabel: String
    let hysteresisFormat: String
    let rampRateFormat: String
    let addCurveButton: String
    let deleteCurveButton: String
    let noCurvesConfigured: String
    let instructionsHint: String
    let userspaceWarning: String
}

extension FeatureStrings {
    static func fanControl(_ language: AppLanguage) -> FanControlFeatureStrings {
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
        }
    }
}

extension L10n {
    var fanControl: FanControlFeatureStrings {
        FeatureStrings.fanControl(language)
    }
}

extension FanControlFeatureStrings {
    static let enUS = FanControlFeatureStrings(
        title: "Fan & Cooling Control",
        fansHeader: "Fans",
        fanHeaderFormat: "Fan %d",
        speedLabel: "Speed",
        modeLabel: "Control Mode",
        autoMode: "Auto",
        manualMode: "Manual",
        customCurveMode: "Custom Curve",
        targetPwmLabel: "Target Speed",
        maxSpeedButton: "Max Speed",
        allAutoButton: "All Auto",
        maxSpeedConfirmationTitle: "Set all fans to maximum speed?",
        maxSpeedConfirmationMessage: "This will run all system fans at 100% PWM (full speed).",
        confirmButton: "Set to Max",
        cancelButton: "Cancel",
        fanCurvesSection: "Custom Fan Curves",
        curveNameLabel: "Curve Name",
        sourceSensorLabel: "Sensor",
        hysteresisLabel: "Hysteresis",
        rampRateLabel: "Ramp Rate",
        hysteresisFormat: "±%.1f °C",
        rampRateFormat: "%.0f %%/s",
        addCurveButton: "New Curve",
        deleteCurveButton: "Delete Curve",
        noCurvesConfigured: "No custom curves configured.",
        instructionsHint: "Click empty space to add a point (max 8). Double-click or right-click a point to delete.",
        userspaceWarning: "Userspace fan curves require RyzenStatus to remain running."
    )

    static let es = FanControlFeatureStrings(
        title: "Control de Ventiladores y Refrigeración",
        fansHeader: "Ventiladores",
        fanHeaderFormat: "Ventilador %d",
        speedLabel: "Velocidad",
        modeLabel: "Modo de Control",
        autoMode: "Automático",
        manualMode: "Manual",
        customCurveMode: "Curva Personalizada",
        targetPwmLabel: "Velocidad Objetivo",
        maxSpeedButton: "Velocidad Máxima",
        allAutoButton: "Todo en Automático",
        maxSpeedConfirmationTitle: "¿Ajustar todos los ventiladores al máximo?",
        maxSpeedConfirmationMessage: "Esto pondrá todos los ventiladores del sistema al 100% de potencia.",
        confirmButton: "Ajustar al Máximo",
        cancelButton: "Cancelar",
        fanCurvesSection: "Curvas de Ventilador",
        curveNameLabel: "Nombre de la Curva",
        sourceSensorLabel: "Sensor",
        hysteresisLabel: "Histéresis",
        rampRateLabel: "Tasa de Rampa",
        hysteresisFormat: "±%.1f °C",
        rampRateFormat: "%.0f %%/s",
        addCurveButton: "Nueva Curva",
        deleteCurveButton: "Eliminar Curva",
        noCurvesConfigured: "No hay curvas personalizadas configuradas.",
        instructionsHint: "Haz clic en el espacio vacío para añadir un punto (máx 8). Doble clic o clic derecho para eliminar.",
        userspaceWarning: "Las curvas en espacio de usuario requieren que RyzenStatus permanezca en ejecución."
    )

    static let ptBR = FanControlFeatureStrings(
        title: "Controle de Ventoinhas e Refrigeração",
        fansHeader: "Ventoinhas",
        fanHeaderFormat: "Ventoinha %d",
        speedLabel: "Velocidade",
        modeLabel: "Modo de Controle",
        autoMode: "Automático",
        manualMode: "Manual",
        customCurveMode: "Curva Personalizada",
        targetPwmLabel: "Velocidade Alvo",
        maxSpeedButton: "Velocidade Máxima",
        allAutoButton: "Tudo Automático",
        maxSpeedConfirmationTitle: "Ajustar todas as ventoinhas para velocidade máxima?",
        maxSpeedConfirmationMessage: "Isso colocará todas as ventoinhas em 100% de PWM.",
        confirmButton: "Velocidade Máxima",
        cancelButton: "Cancelar",
        fanCurvesSection: "Curvas Personalizadas",
        curveNameLabel: "Nome da Curva",
        sourceSensorLabel: "Sensor",
        hysteresisLabel: "Histerese",
        rampRateLabel: "Taxa de Rampa",
        hysteresisFormat: "±%.1f °C",
        rampRateFormat: "%.0f %%/s",
        addCurveButton: "Nova Curva",
        deleteCurveButton: "Excluir Curva",
        noCurvesConfigured: "Nenhuma curva personalizada configurada.",
        instructionsHint: "Clique no espaço vazio para adicionar um ponto (máx 8). Clique duplo ou botão direito para remover.",
        userspaceWarning: "Curvas em espaço de usuário exigem que o RyzenStatus continue em execução."
    )

    static let de = FanControlFeatureStrings(
        title: "Lüfter- & Kühlungssteuerung",
        fansHeader: "Lüfter",
        fanHeaderFormat: "Lüfter %d",
        speedLabel: "Drehzahl",
        modeLabel: "Steuerungsmodus",
        autoMode: "Automatisch",
        manualMode: "Manuell",
        customCurveMode: "Benutzerdefinierte Kurve",
        targetPwmLabel: "Ziel-PWM",
        maxSpeedButton: "Volle Leistung",
        allAutoButton: "Alle Automatisch",
        maxSpeedConfirmationTitle: "Alle Lüfter auf Maximalgeschwindigkeit setzen?",
        maxSpeedConfirmationMessage: "Dadurch laufen alle Lüfter mit 100% PWM.",
        confirmButton: "Maximieren",
        cancelButton: "Abbrechen",
        fanCurvesSection: "Lüfterkurven",
        curveNameLabel: "Kurvenname",
        sourceSensorLabel: "Sensor",
        hysteresisLabel: "Hysterese",
        rampRateLabel: "Rampenrate",
        hysteresisFormat: "±%.1f °C",
        rampRateFormat: "%.0f %%/s",
        addCurveButton: "Neue Kurve",
        deleteCurveButton: "Kurve löschen",
        noCurvesConfigured: "Keine Lüfterkurven konfiguriert.",
        instructionsHint: "Klicken Sie in den leeren Bereich, um einen Punkt hinzuzufügen (max. 8). Doppelklick oder Rechtsklick zum Löschen.",
        userspaceWarning: "Lüfterkurven im Userspace erfordern, dass RyzenStatus geöffnet bleibt."
    )

    static let fr = FanControlFeatureStrings(
        title: "Contrôle des Ventilateurs et Refroidissement",
        fansHeader: "Ventilateurs",
        fanHeaderFormat: "Ventilateur %d",
        speedLabel: "Vitesse",
        modeLabel: "Mode de contrôle",
        autoMode: "Automatique",
        manualMode: "Manuel",
        customCurveMode: "Courbe personnalisée",
        targetPwmLabel: "Vitesse cible",
        maxSpeedButton: "Vitesse maximale",
        allAutoButton: "Tout automatique",
        maxSpeedConfirmationTitle: "Régler tous les ventilateurs à la vitesse maximale ?",
        maxSpeedConfirmationMessage: "Tous les ventilateurs fonctionneront à 100% PWM.",
        confirmButton: "Vitesse Max",
        cancelButton: "Annuler",
        fanCurvesSection: "Courbes de ventilation",
        curveNameLabel: "Nom de la courbe",
        sourceSensorLabel: "Capteur",
        hysteresisLabel: "Hystérésis",
        rampRateLabel: "Taux de variation",
        hysteresisFormat: "±%.1f °C",
        rampRateFormat: "%.0f %%/s",
        addCurveButton: "Nouvelle courbe",
        deleteCurveButton: "Supprimer la courbe",
        noCurvesConfigured: "Aucune courbe personnalisée configurée.",
        instructionsHint: "Cliquez sur un espace vide pour ajouter un point (max 8). Double-clic ou clic droit pour supprimer.",
        userspaceWarning: "Les courbes en espace utilisateur nécessitent que RyzenStatus reste ouvert."
    )

    static let it = FanControlFeatureStrings(
        title: "Controllo Ventole e Raffreddamento",
        fansHeader: "Ventole",
        fanHeaderFormat: "Ventola %d",
        speedLabel: "Velocità",
        modeLabel: "Modalità di controllo",
        autoMode: "Automatico",
        manualMode: "Manuale",
        customCurveMode: "Curva personalizzata",
        targetPwmLabel: "Velocità desiderata",
        maxSpeedButton: "Velocità massima",
        allAutoButton: "Tutto automatico",
        maxSpeedConfirmationTitle: "Impostare tutte le ventole alla velocità massima?",
        maxSpeedConfirmationMessage: "Tutte le ventole funzioneranno al 100% PWM.",
        confirmButton: "Velocità Max",
        cancelButton: "Annulla",
        fanCurvesSection: "Curve delle ventole",
        curveNameLabel: "Nome curva",
        sourceSensorLabel: "Sensore",
        hysteresisLabel: "Isteresi",
        rampRateLabel: "Velocità rampa",
        hysteresisFormat: "±%.1f °C",
        rampRateFormat: "%.0f %%/s",
        addCurveButton: "Nuova curva",
        deleteCurveButton: "Elimina curva",
        noCurvesConfigured: "Nessuna curva personalizzata configurata.",
        instructionsHint: "Fai clic su uno spazio vuoto per aggiungere un punto (max 8). Doppio clic o clic destro per eliminare.",
        userspaceWarning: "Le curve in userspace richiedono che RyzenStatus rimanga in esecuzione."
    )

    static let ru = FanControlFeatureStrings(
        title: "Управление вентиляторами и охлаждением",
        fansHeader: "Вентиляторы",
        fanHeaderFormat: "Вентилятор %d",
        speedLabel: "Скорость",
        modeLabel: "Режим управления",
        autoMode: "Авто",
        manualMode: "Вручную",
        customCurveMode: "Пользовательская кривая",
        targetPwmLabel: "Целевая скорость",
        maxSpeedButton: "Макс. скорость",
        allAutoButton: "Все в авто",
        maxSpeedConfirmationTitle: "Установить все вентиляторы на максимум?",
        maxSpeedConfirmationMessage: "Все вентиляторы системы будут работать на 100% ШИМ.",
        confirmButton: "На максимум",
        cancelButton: "Отмена",
        fanCurvesSection: "Кривые вентиляторов",
        curveNameLabel: "Название кривой",
        sourceSensorLabel: "Датчик",
        hysteresisLabel: "Гистерезис",
        rampRateLabel: "Скорость изменения",
        hysteresisFormat: "±%.1f °C",
        rampRateFormat: "%.0f %%/с",
        addCurveButton: "Новая кривая",
        deleteCurveButton: "Удалить кривую",
        noCurvesConfigured: "Пользовательские кривые не настроены.",
        instructionsHint: "Нажмите на пустое место, чтобы добавить точку (макс. 8). Двойной клик или правая кнопка для удаления.",
        userspaceWarning: "Кривые вентиляторов требуют, чтобы приложение RyzenStatus оставалось запущенным."
    )

    static let tr = FanControlFeatureStrings(
        title: "Fan ve Soğutma Kontrolü",
        fansHeader: "Fanlar",
        fanHeaderFormat: "Fan %d",
        speedLabel: "Hız",
        modeLabel: "Kontrol Modu",
        autoMode: "Otomatik",
        manualMode: "Manuel",
        customCurveMode: "Özel Eğri",
        targetPwmLabel: "Hedef Hız",
        maxSpeedButton: "Maks Hız",
        allAutoButton: "Tümü Otomatik",
        maxSpeedConfirmationTitle: "Tüm fanlar maksimum hıza ayarlansın mı?",
        maxSpeedConfirmationMessage: "Tüm sistem fanları %100 PWM ile tam hızda çalışacaktır.",
        confirmButton: "Maksimuma Ayarla",
        cancelButton: "İptal",
        fanCurvesSection: "Özel Fan Eğrileri",
        curveNameLabel: "Eğri Adı",
        sourceSensorLabel: "Sensör",
        hysteresisLabel: "Histerezis",
        rampRateLabel: "Geçiş Hızı",
        hysteresisFormat: "±%.1f °C",
        rampRateFormat: "%.0f %%/s",
        addCurveButton: "Yeni Eğri",
        deleteCurveButton: "Eğriyi Sil",
        noCurvesConfigured: "Yapılandırılmış özel eğri yok.",
        instructionsHint: "Nokta eklemek için boş alana tıklayın (maks 8). Silmek için çift tıklayın veya sağ tıklayın.",
        userspaceWarning: "Kullanıcı alanı fan eğrileri, RyzenStatus'un çalışır durumda kalmasını gerektirir."
    )

    static let ja = FanControlFeatureStrings(
        title: "ファン・冷却コントロール",
        fansHeader: "ファン",
        fanHeaderFormat: "ファン %d",
        speedLabel: "回転数",
        modeLabel: "制御モード",
        autoMode: "自動",
        manualMode: "手動",
        customCurveMode: "カスタムカーブ",
        targetPwmLabel: "目標速度",
        maxSpeedButton: "最大速度",
        allAutoButton: "すべて自動",
        maxSpeedConfirmationTitle: "すべてのファンを最大速度に設定しますか？",
        maxSpeedConfirmationMessage: "すべてのシステムファンが100% PWM（全開）で動作します。",
        confirmButton: "最大に設定",
        cancelButton: "キャンセル",
        fanCurvesSection: "ファンカーブ設定",
        curveNameLabel: "カーブ名",
        sourceSensorLabel: "センサー",
        hysteresisLabel: "ヒステリシス",
        rampRateLabel: "変化レート",
        hysteresisFormat: "±%.1f °C",
        rampRateFormat: "%.0f %%/秒",
        addCurveButton: "新規カーブ",
        deleteCurveButton: "カーブを削除",
        noCurvesConfigured: "カスタムカーブが設定されていません。",
        instructionsHint: "空白をクリックしてポイントを追加（最大8個）。ダブルクリックまたは右クリックで削除。",
        userspaceWarning: "ユーザー空間のファンカーブはRyzenStatusが起動中のみ有効です。"
    )

    static let ko = FanControlFeatureStrings(
        title: "팬 및 쿨링 제어",
        fansHeader: "팬",
        fanHeaderFormat: "팬 %d",
        speedLabel: "속도",
        modeLabel: "제어 모드",
        autoMode: "자동",
        manualMode: "수동",
        customCurveMode: "사용자 정의 곡선",
        targetPwmLabel: "목표 속도",
        maxSpeedButton: "최대 속도",
        allAutoButton: "모두 자동",
        maxSpeedConfirmationTitle: "모든 팬을 최대 속도로 설정하시겠습니까?",
        maxSpeedConfirmationMessage: "모든 시스템 팬이 100% PWM(최대 속도)으로 작동합니다.",
        confirmButton: "최대로 설정",
        cancelButton: "취소",
        fanCurvesSection: "팬 곡선 설정",
        curveNameLabel: "곡선 이름",
        sourceSensorLabel: "센서",
        hysteresisLabel: "히스테리시스",
        rampRateLabel: "변화율",
        hysteresisFormat: "±%.1f °C",
        rampRateFormat: "%.0f %%/초",
        addCurveButton: "새 곡선",
        deleteCurveButton: "곡선 삭제",
        noCurvesConfigured: "설정된 사용자 정의 곡선이 없습니다.",
        instructionsHint: "빈 공간을 클릭하여 포인트를 추가하세요 (최대 8개). 더블 클릭 또는 우클릭으로 삭제합니다.",
        userspaceWarning: "사용자 공간 팬 곡선은 RyzenStatus가 실행 중일 때만 동작합니다."
    )

    static let zhHans = FanControlFeatureStrings(
        title: "风扇与散热控制",
        fansHeader: "风扇",
        fanHeaderFormat: "风扇 %d",
        speedLabel: "转速",
        modeLabel: "控制模式",
        autoMode: "自动",
        manualMode: "手动",
        customCurveMode: "自定义曲线",
        targetPwmLabel: "目标转速",
        maxSpeedButton: "全速运转",
        allAutoButton: "全部自动",
        maxSpeedConfirmationTitle: "是否将所有风扇设为最大转速？",
        maxSpeedConfirmationMessage: "这将使所有系统风扇以 100% PWM 全速运转。",
        confirmButton: "设为全速",
        cancelButton: "取消",
        fanCurvesSection: "自定义风扇曲线",
        curveNameLabel: "曲线名称",
        sourceSensorLabel: "温度传感器",
        hysteresisLabel: "回差温度",
        rampRateLabel: "转速变化率",
        hysteresisFormat: "±%.1f °C",
        rampRateFormat: "%.0f %%/秒",
        addCurveButton: "新建曲线",
        deleteCurveButton: "删除曲线",
        noCurvesConfigured: "尚未配置自定义曲线。",
        instructionsHint: "点击空白处添加控制点（最多 8 个）。双击或右键点击以删除控制点。",
        userspaceWarning: "用户态风扇曲线需要保持 RyzenStatus 后台运行。"
    )

    static let zhTW = FanControlFeatureStrings(
        title: "風扇與散熱控制",
        fansHeader: "風扇",
        fanHeaderFormat: "風扇 %d",
        speedLabel: "轉速",
        modeLabel: "控制模式",
        autoMode: "自動",
        manualMode: "手動",
        customCurveMode: "自訂曲線",
        targetPwmLabel: "目標轉速",
        maxSpeedButton: "全速運轉",
        allAutoButton: "全部自動",
        maxSpeedConfirmationTitle: "是否將所有風扇設為最大轉速？",
        maxSpeedConfirmationMessage: "這將使所有系統風扇以 100% PWM 全速運轉。",
        confirmButton: "設為全速",
        cancelButton: "取消",
        fanCurvesSection: "自訂風扇曲線",
        curveNameLabel: "曲線名稱",
        sourceSensorLabel: "溫度感測器",
        hysteresisLabel: "遲滯溫度",
        rampRateLabel: "轉速變化率",
        hysteresisFormat: "±%.1f °C",
        rampRateFormat: "%.0f %%/秒",
        addCurveButton: "新增曲線",
        deleteCurveButton: "刪除曲線",
        noCurvesConfigured: "尚未設定自訂曲線。",
        instructionsHint: "點擊空白處新增控制點（最多 8 個）。連按兩下或右鍵點擊以刪除控制點。",
        userspaceWarning: "使用者空間風扇曲線需要保持 RyzenStatus 背景執行。"
    )

    static let zhHK = zhTW
}
