(*
  FB_CIPManager_v2 — движок CIP «7 циклов × 3 этапа» с редактором уставок
  Требования:
  - Типы только BOOL, UDINT, REAL (OwenLogic)
  - Все переменные объявлены в начале блока (VAR_INPUT / VAR_OUTPUT / VAR)
  - Сетевые регистры 528..533, 569, 570 пробрасываются через *_IN / *_OUT
  - Стандартные (RETAIN) уставки циклов и маски режимов — через *_IN / *_OUT (чтение/запись)
  - Выход CIP_Mixer_ON — использовать в FB_ActuatorManager вместо «мешалка всегда при CIP»
*)

FUNCTION_BLOCK FB_CIPManager_v2

// ============================== ВХОДЫ ==============================
VAR_INPUT
    // — Управление режимами CIP (уровневые) —
    CIP_Full_RunReq   : BOOL;  // Полный режим
    CIP_Alk_RunReq    : BOOL;  // Щелочная программа
    CIP_Acid_RunReq   : BOOL;  // Кислотная программа
    CIP_Rinse_RunReq  : BOOL;  // Только ополаскивание

    // — Безопасность / аварии —
    CMD_Stop          : BOOL;  // немедленный принудительный стоп
    ALM_NoWater       : BOOL;  // авария «нет воды»

    // — Секундный тик (из MAIN) —
    Seconds_UD        : UDINT;

    // ================== СЕТЕВЫЕ (Slot1), ВХОДЫ HMI ==================
    // 528: выбор цикла/флаги мешалки/LiveWrite/ModeSel/ошибка мультивыбора
    MB_CIP_Edit_SEL_IN      : UDINT; // b0..b6=выбор цикла (one-hot), b7=LiveWrite, b8..b10=мешалка S1..S3, b11..b13=ModeSel, b14=MultiSelErr (читаем)
    // 529..533, 570: уставки активного цикла (сек)
    MB_CIP_Edit_T_HOT_IN    : UDINT; // 529
    MB_CIP_Edit_T_COLD_IN   : UDINT; // 530
    MB_CIP_Edit_T_ALK_IN    : UDINT; // 531
    MB_CIP_Edit_T_ACID_IN   : UDINT; // 532
    MB_CIP_Edit_T_PUMP_IN   : UDINT; // 533
    MB_CIP_Edit_T_DRAIN_IN  : UDINT; // 570
    // 569: маска циклов выбранного режима (биты 0..6 = циклы 1..7)
    MB_CIP_Edit_MASK_IN     : UDINT; // 569

    // ================== СТАНДАРТНЫЕ (RETAIN), ВХОДЫ ==================
    // Маски составов режимов (биты 0..6 соответствуют циклам 1..7)
    CIP_ModeMask_Full_IN    : UDINT;
    CIP_ModeMask_Alk_IN     : UDINT;
    CIP_ModeMask_Acid_IN    : UDINT;
    CIP_ModeMask_Rinse_IN   : UDINT;

    // Политики / параметры
    CIP_DrainOnStopSec_IN        : UDINT; // «вежливый» слив при корректном стопе
    CIP_ChemConflictPolicy_IN    : UDINT; // 0=запрет ALK+ACID, 1=приоритет ALK, 2=приоритет ACID
    CIP_LiveWriteCommitDelay_s_IN: UDINT; // задержка коммита «живой» записи

    // Уставки циклов 1..7 — ВХОДЫ (текущие значения из RETAIN)
    CIP_C1_T_HOT_s_IN,   CIP_C1_T_COLD_s_IN,   CIP_C1_T_ALK_s_IN,   CIP_C1_T_ACID_s_IN,   CIP_C1_T_PUMP_s_IN,   CIP_C1_T_DRAIN_s_IN : UDINT;
    CIP_C1_MixerStage1_IN, CIP_C1_MixerStage2_IN, CIP_C1_MixerStage3_IN : BOOL;

    CIP_C2_T_HOT_s_IN,   CIP_C2_T_COLD_s_IN,   CIP_C2_T_ALK_s_IN,   CIP_C2_T_ACID_s_IN,   CIP_C2_T_PUMP_s_IN,   CIP_C2_T_DRAIN_s_IN : UDINT;
    CIP_C2_MixerStage1_IN, CIP_C2_MixerStage2_IN, CIP_C2_MixerStage3_IN : BOOL;

    CIP_C3_T_HOT_s_IN,   CIP_C3_T_COLD_s_IN,   CIP_C3_T_ALK_s_IN,   CIP_C3_T_ACID_s_IN,   CIP_C3_T_PUMP_s_IN,   CIP_C3_T_DRAIN_s_IN : UDINT;
    CIP_C3_MixerStage1_IN, CIP_C3_MixerStage2_IN, CIP_C3_MixerStage3_IN : BOOL;

    CIP_C4_T_HOT_s_IN,   CIP_C4_T_COLD_s_IN,   CIP_C4_T_ALK_s_IN,   CIP_C4_T_ACID_s_IN,   CIP_C4_T_PUMP_s_IN,   CIP_C4_T_DRAIN_s_IN : UDINT;
    CIP_C4_MixerStage1_IN, CIP_C4_MixerStage2_IN, CIP_C4_MixerStage3_IN : BOOL;

    CIP_C5_T_HOT_s_IN,   CIP_C5_T_COLD_s_IN,   CIP_C5_T_ALK_s_IN,   CIP_C5_T_ACID_s_IN,   CIP_C5_T_PUMP_s_IN,   CIP_C5_T_DRAIN_s_IN : UDINT;
    CIP_C5_MixerStage1_IN, CIP_C5_MixerStage2_IN, CIP_C5_MixerStage3_IN : BOOL;

    CIP_C6_T_HOT_s_IN,   CIP_C6_T_COLD_s_IN,   CIP_C6_T_ALK_s_IN,   CIP_C6_T_ACID_s_IN,   CIP_C6_T_PUMP_s_IN,   CIP_C6_T_DRAIN_s_IN : UDINT;
    CIP_C6_MixerStage1_IN, CIP_C6_MixerStage2_IN, CIP_C6_MixerStage3_IN : BOOL;

    CIP_C7_T_HOT_s_IN,   CIP_C7_T_COLD_s_IN,   CIP_C7_T_ALK_s_IN,   CIP_C7_T_ACID_s_IN,   CIP_C7_T_PUMP_s_IN,   CIP_C7_T_DRAIN_s_IN : UDINT;
    CIP_C7_MixerStage1_IN, CIP_C7_MixerStage2_IN, CIP_C7_MixerStage3_IN : BOOL;
END_VAR

// ============================== ВЫХОДЫ =============================
VAR_OUTPUT
    // — Команды на актуатор —
    CIP_Valve_Cold_ON : BOOL;
    CIP_Valve_Hot_ON  : BOOL;
    CIP_Valve_Alk_ON  : BOOL;
    CIP_Valve_Acid_ON : BOOL;
    CIP_Pump_ON       : BOOL;
    CIP_DrainValve_ON : BOOL;
    CIP_Mixer_ON      : BOOL;

    // — Статусы —
    StageMask_CIP     : UDINT; // бит0=этап1, бит1=этап2, бит2=этап3
    Mode_ACTIVE       : BOOL;
    ActiveModeCode    : UDINT; // 0=нет,1=Full,2=Alk,3=Acid,4=Rinse
    ActiveCycleNo     : UDINT; // 1..7
    ActiveStageNo     : UDINT; // 1..3
    Timer_StageSec    : UDINT;

    // ================== СЕТЕВЫЕ (Slot1), ВЫХОДЫ к HMI ==================
    MB_CIP_Edit_SEL_OUT      : UDINT; // дублируем селект + биты мешалки + MultiSelErr
    MB_CIP_Edit_T_HOT_OUT    : UDINT; // 529
    MB_CIP_Edit_T_COLD_OUT   : UDINT; // 530
    MB_CIP_Edit_T_ALK_OUT    : UDINT; // 531
    MB_CIP_Edit_T_ACID_OUT   : UDINT; // 532
    MB_CIP_Edit_T_PUMP_OUT   : UDINT; // 533
    MB_CIP_Edit_T_DRAIN_OUT  : UDINT; // 570
    MB_CIP_Edit_MASK_OUT     : UDINT; // 569

    // ================== СТАНДАРТНЫЕ (RETAIN), ВЫХОДЫ ==================
    // Маски режимов (обновляются при редактировании в 569)
    CIP_ModeMask_Full_OUT    : UDINT;
    CIP_ModeMask_Alk_OUT     : UDINT;
    CIP_ModeMask_Acid_OUT    : UDINT;
    CIP_ModeMask_Rinse_OUT   : UDINT;

    // Параметры (сквозная передача; можно соединить OUT=IN на схеме)
    CIP_DrainOnStopSec_OUT        : UDINT;
    CIP_ChemConflictPolicy_OUT    : UDINT;
    CIP_LiveWriteCommitDelay_s_OUT: UDINT;

    // Уставки циклов 1..7 — ВЫХОДЫ (для «живой» записи RETAIN)
    CIP_C1_T_HOT_s_OUT,   CIP_C1_T_COLD_s_OUT,   CIP_C1_T_ALK_s_OUT,   CIP_C1_T_ACID_s_OUT,   CIP_C1_T_PUMP_s_OUT,   CIP_C1_T_DRAIN_s_OUT : UDINT;
    CIP_C1_MixerStage1_OUT, CIP_C1_MixerStage2_OUT, CIP_C1_MixerStage3_OUT : BOOL;

    CIP_C2_T_HOT_s_OUT,   CIP_C2_T_COLD_s_OUT,   CIP_C2_T_ALK_s_OUT,   CIP_C2_T_ACID_s_OUT,   CIP_C2_T_PUMP_s_OUT,   CIP_C2_T_DRAIN_s_OUT : UDINT;
    CIP_C2_MixerStage1_OUT, CIP_C2_MixerStage2_OUT, CIP_C2_MixerStage3_OUT : BOOL;

    CIP_C3_T_HOT_s_OUT,   CIP_C3_T_COLD_s_OUT,   CIP_C3_T_ALK_s_OUT,   CIP_C3_T_ACID_s_OUT,   CIP_C3_T_PUMP_s_OUT,   CIP_C3_T_DRAIN_s_OUT : UDINT;
    CIP_C3_MixerStage1_OUT, CIP_C3_MixerStage2_OUT, CIP_C3_MixerStage3_OUT : BOOL;

    CIP_C4_T_HOT_s_OUT,   CIP_C4_T_COLD_s_OUT,   CIP_C4_T_ALK_s_OUT,   CIP_C4_T_ACID_s_OUT,   CIP_C4_T_PUMP_s_OUT,   CIP_C4_T_DRAIN_s_OUT : UDINT;
    CIP_C4_MixerStage1_OUT, CIP_C4_MixerStage2_OUT, CIP_C4_MixerStage3_OUT : BOOL;

    CIP_C5_T_HOT_s_OUT,   CIP_C5_T_COLD_s_OUT,   CIP_C5_T_ALK_s_OUT,   CIP_C5_T_ACID_s_OUT,   CIP_C5_T_PUMP_s_OUT,   CIP_C5_T_DRAIN_s_OUT : UDINT;
    CIP_C5_MixerStage1_OUT, CIP_C5_MixerStage2_OUT, CIP_C5_MixerStage3_OUT : BOOL;

    CIP_C6_T_HOT_s_OUT,   CIP_C6_T_COLD_s_OUT,   CIP_C6_T_ALK_s_OUT,   CIP_C6_T_ACID_s_OUT,   CIP_C6_T_PUMP_s_OUT,   CIP_C6_T_DRAIN_s_OUT : UDINT;
    CIP_C6_MixerStage1_OUT, CIP_C6_MixerStage2_OUT, CIP_C6_MixerStage3_OUT : BOOL;

    CIP_C7_T_HOT_s_OUT,   CIP_C7_T_COLD_s_OUT,   CIP_C7_T_ALK_s_OUT,   CIP_C7_T_ACID_s_OUT,   CIP_C7_T_PUMP_s_OUT,   CIP_C7_T_DRAIN_s_OUT : UDINT;
    CIP_C7_MixerStage1_OUT, CIP_C7_MixerStage2_OUT, CIP_C7_MixerStage3_OUT : BOOL;
END_VAR

// ============================== ВНУТРЕННИЕ =========================
VAR
    // Инициализация/состояния
    init_done       : BOOL;
    state           : UDINT;      // 0=IDLE,1=RUN,2=STOPPING
    stage           : UDINT;      // 0=нет,1..3
    curIdx          : UDINT;      // индекс в очереди cyclesQueue[1..7]
    cyclesCount     : UDINT;      // сколько циклов в очереди
    lastSec_UD      : UDINT;
    t_stage         : UDINT;      // таймер текущего этапа
    t_stopDrain     : UDINT;      // таймер корректного слива
    modeChosen      : UDINT;      // 0=нет,1=Full,2=Alk,3=Acid,4=Rinse

    // Очередь циклов под выбранный режим
    cyclesQueue1    : UDINT;
    cyclesQueue2    : UDINT;
    cyclesQueue3    : UDINT;
    cyclesQueue4    : UDINT;
    cyclesQueue5    : UDINT;
    cyclesQueue6    : UDINT;
    cyclesQueue7    : UDINT;

    // Локальные уставки активного цикла (снимок)
    U_T_HOT         : UDINT;
    U_T_COLD        : UDINT;
    U_T_ALK         : UDINT;
    U_T_ACID        : UDINT;
    U_T_PUMP        : UDINT;
    U_T_DRAIN       : UDINT;
    U_Mix_S1        : BOOL;
    U_Mix_S2        : BOOL;
    U_Mix_S3        : BOOL;

    // Редактор (детект изменений)
    activeEditCycle : UDINT;      // 0=нет, 1..7
    dirty           : BOOL;
    lastEditSec     : UDINT;

    // Зеркала сетевых уставок (для детектора изменений)
    t_prev_hot      : UDINT;
    t_prev_cold     : UDINT;
    t_prev_alk      : UDINT;
    t_prev_acid     : UDINT;
    t_prev_pump     : UDINT;
    t_prev_drain    : UDINT;
    sel_prev        : UDINT;
    mask_prev       : UDINT;

    // Вспомогательные
    runReqAny       : BOOL;
    t1_max          : UDINT;
    alk_en          : BOOL;
    acid_en         : BOOL;

    // Служебные для циклов/битовых операций
    i               : UDINT;      // индекс 0..6 для обработки выбора цикла
    onesCount       : UDINT;      // число выставленных битов в MB_CIP_Edit_SEL_IN b0..b6
    newActive       : UDINT;      // кандидат выбранного цикла 1..7
    liveWrite       : BOOL;       // MB_CIP_Edit_SEL_IN.b7
    modeSelBits     : UDINT;      // MB_CIP_Edit_SEL_IN.b11..b13
END_VAR


// ===================== ПАСС-ТРУ параметров =====================
CIP_DrainOnStopSec_OUT         := CIP_DrainOnStopSec_IN;
CIP_ChemConflictPolicy_OUT     := CIP_ChemConflictPolicy_IN;
CIP_LiveWriteCommitDelay_s_OUT := CIP_LiveWriteCommitDelay_s_IN;

// ===================== ИНИЦИАЛИЗАЦИЯ =====================
IF NOT init_done THEN
    CIP_Valve_Cold_ON := FALSE; CIP_Valve_Hot_ON  := FALSE;
    CIP_Valve_Alk_ON  := FALSE; CIP_Valve_Acid_ON := FALSE;
    CIP_Pump_ON := FALSE; CIP_DrainValve_ON := FALSE; CIP_Mixer_ON := FALSE;

    StageMask_CIP := 0; Mode_ACTIVE := FALSE;
    ActiveModeCode := 0; ActiveCycleNo := 0; ActiveStageNo := 0;
    state := 0; stage := 0; curIdx := 0; cyclesCount := 0;
    lastSec_UD := Seconds_UD; t_stage := 0; t_stopDrain := 0; modeChosen := 0;

    cyclesQueue1 := 0; cyclesQueue2 := 0; cyclesQueue3 := 0; cyclesQueue4 := 0;
    cyclesQueue5 := 0; cyclesQueue6 := 0; cyclesQueue7 := 0;

    // Зеркала редактора
    sel_prev  := MB_CIP_Edit_SEL_IN;
    mask_prev := MB_CIP_Edit_MASK_IN;
    t_prev_hot   := MB_CIP_Edit_T_HOT_IN;
    t_prev_cold  := MB_CIP_Edit_T_COLD_IN;
    t_prev_alk   := MB_CIP_Edit_T_ALK_IN;
    t_prev_acid  := MB_CIP_Edit_T_ACID_IN;
    t_prev_pump  := MB_CIP_Edit_T_PUMP_IN;
    t_prev_drain := MB_CIP_Edit_T_DRAIN_IN;
    activeEditCycle := 0; dirty := FALSE; lastEditSec := Seconds_UD;

    // Инициализация OUT для HMI
    MB_CIP_Edit_SEL_OUT     := MB_CIP_Edit_SEL_IN;
    MB_CIP_Edit_T_HOT_OUT   := MB_CIP_Edit_T_HOT_IN;
    MB_CIP_Edit_T_COLD_OUT  := MB_CIP_Edit_T_COLD_IN;
    MB_CIP_Edit_T_ALK_OUT   := MB_CIP_Edit_T_ALK_IN;
    MB_CIP_Edit_T_ACID_OUT  := MB_CIP_Edit_T_ACID_IN;
    MB_CIP_Edit_T_PUMP_OUT  := MB_CIP_Edit_T_PUMP_IN;
    MB_CIP_Edit_T_DRAIN_OUT := MB_CIP_Edit_T_DRAIN_IN;
    MB_CIP_Edit_MASK_OUT    := MB_CIP_Edit_MASK_IN;

    // Маски режимов OUT = IN
    CIP_ModeMask_Full_OUT  := CIP_ModeMask_Full_IN;
    CIP_ModeMask_Alk_OUT   := CIP_ModeMask_Alk_IN;
    CIP_ModeMask_Acid_OUT  := CIP_ModeMask_Acid_IN;
    CIP_ModeMask_Rinse_OUT := CIP_ModeMask_Rinse_IN;

    init_done := TRUE;
END_IF;

// ===================== СЕКУНДНЫЙ ТИК =====================
IF Seconds_UD <> lastSec_UD THEN
    lastSec_UD := Seconds_UD;
    IF state = 1 THEN t_stage := t_stage + 1; END_IF;
    IF state = 2 THEN t_stopDrain := t_stopDrain + 1; END_IF;
END_IF;

// ===================== РЕДАКТОР (528.., 569, 570) =====================
// Подсчёт выбранных циклов (b0..b6), определение активного
onesCount := 0; newActive := 0;
IF MB_CIP_Edit_SEL_IN.0 THEN onesCount := onesCount + 1; newActive := 1; END_IF;
IF MB_CIP_Edit_SEL_IN.1 THEN onesCount := onesCount + 1; newActive := 2; END_IF;
IF MB_CIP_Edit_SEL_IN.2 THEN onesCount := onesCount + 1; newActive := 3; END_IF;
IF MB_CIP_Edit_SEL_IN.3 THEN onesCount := onesCount + 1; newActive := 4; END_IF;
IF MB_CIP_Edit_SEL_IN.4 THEN onesCount := onesCount + 1; newActive := 5; END_IF;
IF MB_CIP_Edit_SEL_IN.5 THEN onesCount := onesCount + 1; newActive := 6; END_IF;
IF MB_CIP_Edit_SEL_IN.6 THEN onesCount := onesCount + 1; newActive := 7; END_IF;

// liveWrite и флаги мешалки с панели
liveWrite := MB_CIP_Edit_SEL_IN.7;
U_Mix_S1 := MB_CIP_Edit_SEL_IN.8;
U_Mix_S2 := MB_CIP_Edit_SEL_IN.9;
U_Mix_S3 := MB_CIP_Edit_SEL_IN.10;

// Выбор редактируемого режима по b11..b13 (иначе Rinse)
IF MB_CIP_Edit_SEL_IN.11 THEN
    modeSelBits := 1;  // Full
ELSIF MB_CIP_Edit_SEL_IN.12 THEN
    modeSelBits := 2;  // Alk
ELSIF MB_CIP_Edit_SEL_IN.13 THEN
    modeSelBits := 3;  // Acid
ELSE
    modeSelBits := 4;  // Rinse
END_IF;

// Обновить SEL_OUT и выставить b14 (ошибка мультивыбора)
MB_CIP_Edit_SEL_OUT := MB_CIP_Edit_SEL_IN;
MB_CIP_Edit_SEL_OUT.14 := (onesCount <> 1);

// Загрузка уставок выбранного цикла в редактор (при смене выбора)
IF (onesCount = 1) AND (newActive <> activeEditCycle) THEN
    activeEditCycle := newActive;

    CASE activeEditCycle OF
    1: U_T_HOT:=CIP_C1_T_HOT_s_IN; U_T_COLD:=CIP_C1_T_COLD_s_IN; U_T_ALK:=CIP_C1_T_ALK_s_IN; U_T_ACID:=CIP_C1_T_ACID_s_IN; U_T_PUMP:=CIP_C1_T_PUMP_s_IN; U_T_DRAIN:=CIP_C1_T_DRAIN_s_IN; U_Mix_S1:=CIP_C1_MixerStage1_IN; U_Mix_S2:=CIP_C1_MixerStage2_IN; U_Mix_S3:=CIP_C1_MixerStage3_IN;
    2: U_T_HOT:=CIP_C2_T_HOT_s_IN; U_T_COLD:=CIP_C2_T_COLD_s_IN; U_T_ALK:=CIP_C2_T_ALK_s_IN; U_T_ACID:=CIP_C2_T_ACID_s_IN; U_T_PUMP:=CIP_C2_T_PUMP_s_IN; U_T_DRAIN:=CIP_C2_T_DRAIN_s_IN; U_Mix_S1:=CIP_C2_MixerStage1_IN; U_Mix_S2:=CIP_C2_MixerStage2_IN; U_Mix_S3:=CIP_C2_MixerStage3_IN;
    3: U_T_HOT:=CIP_C3_T_HOT_s_IN; U_T_COLD:=CIP_C3_T_COLD_s_IN; U_T_ALK:=CIP_C3_T_ALK_s_IN; U_T_ACID:=CIP_C3_T_ACID_s_IN; U_T_PUMP:=CIP_C3_T_PUMP_s_IN; U_T_DRAIN:=CIP_C3_T_DRAIN_s_IN; U_Mix_S1:=CIP_C3_MixerStage1_IN; U_Mix_S2:=CIP_C3_MixerStage2_IN; U_Mix_S3:=CIP_C3_MixerStage3_IN;
    4: U_T_HOT:=CIP_C4_T_HOT_s_IN; U_T_COLD:=CIP_C4_T_COLD_s_IN; U_T_ALK:=CIP_C4_T_ALK_s_IN; U_T_ACID:=CIP_C4_T_ACID_s_IN; U_T_PUMP:=CIP_C4_T_PUMP_s_IN; U_T_DRAIN:=CIP_C4_T_DRAIN_s_IN; U_Mix_S1:=CIP_C4_MixerStage1_IN; U_Mix_S2:=CIP_C4_MixerStage2_IN; U_Mix_S3:=CIP_C4_MixerStage3_IN;
    5: U_T_HOT:=CIP_C5_T_HOT_s_IN; U_T_COLD:=CIP_C5_T_COLD_s_IN; U_T_ALK:=CIP_C5_T_ALK_s_IN; U_T_ACID:=CIP_C5_T_ACID_s_IN; U_T_PUMP:=CIP_C5_T_PUMP_s_IN; U_T_DRAIN:=CIP_C5_T_DRAIN_s_IN; U_Mix_S1:=CIP_C5_MixerStage1_IN; U_Mix_S2:=CIP_C5_MixerStage2_IN; U_Mix_S3:=CIP_C5_MixerStage3_IN;
    6: U_T_HOT:=CIP_C6_T_HOT_s_IN; U_T_COLD:=CIP_C6_T_COLD_s_IN; U_T_ALK:=CIP_C6_T_ALK_s_IN; U_T_ACID:=CIP_C6_T_ACID_s_IN; U_T_PUMP:=CIP_C6_T_PUMP_s_IN; U_T_DRAIN:=CIP_C6_T_DRAIN_s_IN; U_Mix_S1:=CIP_C6_MixerStage1_IN; U_Mix_S2:=CIP_C6_MixerStage2_IN; U_Mix_S3:=CIP_C6_MixerStage3_IN;
    7: U_T_HOT:=CIP_C7_T_HOT_s_IN; U_T_COLD:=CIP_C7_T_COLD_s_IN; U_T_ALK:=CIP_C7_T_ALK_s_IN; U_T_ACID:=CIP_C7_T_ACID_s_IN; U_T_PUMP:=CIP_C7_T_PUMP_s_IN; U_T_DRAIN:=CIP_C7_T_DRAIN_s_IN; U_Mix_S1:=CIP_C7_MixerStage1_IN; U_Mix_S2:=CIP_C7_MixerStage2_IN; U_Mix_S3:=CIP_C7_MixerStage3_IN;
    ELSE
        U_T_HOT:=0; U_T_COLD:=0; U_T_ALK:=0; U_T_ACID:=0; U_T_PUMP:=0; U_T_DRAIN:=0; U_Mix_S1:=FALSE; U_Mix_S2:=FALSE; U_Mix_S3:=FALSE;
    END_CASE;

    // Проброс в сетевые OUT
    MB_CIP_Edit_T_HOT_OUT   := U_T_HOT;
    MB_CIP_Edit_T_COLD_OUT  := U_T_COLD;
    MB_CIP_Edit_T_ALK_OUT   := U_T_ALK;
    MB_CIP_Edit_T_ACID_OUT  := U_T_ACID;
    MB_CIP_Edit_T_PUMP_OUT  := U_T_PUMP;
    MB_CIP_Edit_T_DRAIN_OUT := U_T_DRAIN;

    // Обновить биты мешалки (b8..b10) на OUT
    MB_CIP_Edit_SEL_OUT.8  := U_Mix_S1;
    MB_CIP_Edit_SEL_OUT.9  := U_Mix_S2;
    MB_CIP_Edit_SEL_OUT.10 := U_Mix_S3;

    // Обновить «предыдущие»
    t_prev_hot   := MB_CIP_Edit_T_HOT_OUT;
    t_prev_cold  := MB_CIP_Edit_T_COLD_OUT;
    t_prev_alk   := MB_CIP_Edit_T_ALK_OUT;
    t_prev_acid  := MB_CIP_Edit_T_ACID_OUT;
    t_prev_pump  := MB_CIP_Edit_T_PUMP_OUT;
    t_prev_drain := MB_CIP_Edit_T_DRAIN_OUT;
END_IF;

// Эхо IN -> OUT (чтобы панель видела ввод)
IF MB_CIP_Edit_T_HOT_OUT   <> MB_CIP_Edit_T_HOT_IN   THEN MB_CIP_Edit_T_HOT_OUT   := MB_CIP_Edit_T_HOT_IN;   END_IF;
IF MB_CIP_Edit_T_COLD_OUT  <> MB_CIP_Edit_T_COLD_IN  THEN MB_CIP_Edit_T_COLD_OUT  := MB_CIP_Edit_T_COLD_IN;  END_IF;
IF MB_CIP_Edit_T_ALK_OUT   <> MB_CIP_Edit_T_ALK_IN   THEN MB_CIP_Edit_T_ALK_OUT   := MB_CIP_Edit_T_ALK_IN;   END_IF;
IF MB_CIP_Edit_T_ACID_OUT  <> MB_CIP_Edit_T_ACID_IN  THEN MB_CIP_Edit_T_ACID_OUT  := MB_CIP_Edit_T_ACID_IN;  END_IF;
IF MB_CIP_Edit_T_PUMP_OUT  <> MB_CIP_Edit_T_PUMP_IN  THEN MB_CIP_Edit_T_PUMP_OUT  := MB_CIP_Edit_T_PUMP_IN;  END_IF;
IF MB_CIP_Edit_T_DRAIN_OUT <> MB_CIP_Edit_T_DRAIN_IN THEN MB_CIP_Edit_T_DRAIN_OUT := MB_CIP_Edit_T_DRAIN_IN; END_IF;

// Коммит в RETAIN при liveWrite и изменениях
IF (activeEditCycle <> 0) AND (onesCount = 1) AND liveWrite THEN
    IF (t_prev_hot   <> MB_CIP_Edit_T_HOT_IN)   OR
       (t_prev_cold  <> MB_CIP_Edit_T_COLD_IN)  OR
       (t_prev_alk   <> MB_CIP_Edit_T_ALK_IN)   OR
       (t_prev_acid  <> MB_CIP_Edit_T_ACID_IN)  OR
       (t_prev_pump  <> MB_CIP_Edit_T_PUMP_IN)  OR
       (t_prev_drain <> MB_CIP_Edit_T_DRAIN_IN) OR
       (MB_CIP_Edit_SEL_OUT.8  <> MB_CIP_Edit_SEL_IN.8) OR
       (MB_CIP_Edit_SEL_OUT.9  <> MB_CIP_Edit_SEL_IN.9) OR
       (MB_CIP_Edit_SEL_OUT.10 <> MB_CIP_Edit_SEL_IN.10) THEN

        dirty := TRUE;
        lastEditSec := Seconds_UD;

        // Обновить зеркала
        t_prev_hot   := MB_CIP_Edit_T_HOT_IN;
        t_prev_cold  := MB_CIP_Edit_T_COLD_IN;
        t_prev_alk   := MB_CIP_Edit_T_ALK_IN;
        t_prev_acid  := MB_CIP_Edit_T_ACID_IN;
        t_prev_pump  := MB_CIP_Edit_T_PUMP_IN;
        t_prev_drain := MB_CIP_Edit_T_DRAIN_IN;

        // Обновить биты мешалки OUT
        MB_CIP_Edit_SEL_OUT.8  := MB_CIP_Edit_SEL_IN.8;
        MB_CIP_Edit_SEL_OUT.9  := MB_CIP_Edit_SEL_IN.9;
        MB_CIP_Edit_SEL_OUT.10 := MB_CIP_Edit_SEL_IN.10;
    END_IF;

    IF dirty AND (Seconds_UD - lastEditSec >= CIP_LiveWriteCommitDelay_s_IN) THEN
        CASE activeEditCycle OF
        1: CIP_C1_T_HOT_s_OUT:=t_prev_hot;  CIP_C1_T_COLD_s_OUT:=t_prev_cold; CIP_C1_T_ALK_s_OUT:=t_prev_alk; CIP_C1_T_ACID_s_OUT:=t_prev_acid; CIP_C1_T_PUMP_s_OUT:=t_prev_pump; CIP_C1_T_DRAIN_s_OUT:=t_prev_drain;
           CIP_C1_MixerStage1_OUT:=MB_CIP_Edit_SEL_OUT.8; CIP_C1_MixerStage2_OUT:=MB_CIP_Edit_SEL_OUT.9; CIP_C1_MixerStage3_OUT:=MB_CIP_Edit_SEL_OUT.10;
        2: CIP_C2_T_HOT_s_OUT:=t_prev_hot;  CIP_C2_T_COLD_s_OUT:=t_prev_cold; CIP_C2_T_ALK_s_OUT:=t_prev_alk; CIP_C2_T_ACID_s_OUT:=t_prev_acid; CIP_C2_T_PUMP_s_OUT:=t_prev_pump; CIP_C2_T_DRAIN_s_OUT:=t_prev_drain;
           CIP_C2_MixerStage1_OUT:=MB_CIP_Edit_SEL_OUT.8; CIP_C2_MixerStage2_OUT:=MB_CIP_Edit_SEL_OUT.9; CIP_C2_MixerStage3_OUT:=MB_CIP_Edit_SEL_OUT.10;
        3: CIP_C3_T_HOT_s_OUT:=t_prev_hot;  CIP_C3_T_COLD_s_OUT:=t_prev_cold; CIP_C3_T_ALK_s_OUT:=t_prev_alk; CIP_C3_T_ACID_s_OUT:=t_prev_acid; CIP_C3_T_PUMP_s_OUT:=t_prev_pump; CIP_C3_T_DRAIN_s_OUT:=t_prev_drain;
           CIP_C3_MixerStage1_OUT:=MB_CIP_Edit_SEL_OUT.8; CIP_C3_MixerStage2_OUT:=MB_CIP_Edit_SEL_OUT.9; CIP_C3_MixerStage3_OUT:=MB_CIP_Edit_SEL_OUT.10;
        4: CIP_C4_T_HOT_s_OUT:=t_prev_hot;  CIP_C4_T_COLD_s_OUT:=t_prev_cold; CIP_C4_T_ALK_s_OUT:=t_prev_alk; CIP_C4_T_ACID_s_OUT:=t_prev_acid; CIP_C4_T_PUMP_s_OUT:=t_prev_pump; CIP_C4_T_DRAIN_s_OUT:=t_prev_drain;
           CIP_C4_MixerStage1_OUT:=MB_CIP_Edit_SEL_OUT.8; CIP_C4_MixerStage2_OUT:=MB_CIP_Edit_SEL_OUT.9; CIP_C4_MixerStage3_OUT:=MB_CIP_Edit_SEL_OUT.10;
        5: CIP_C5_T_HOT_s_OUT:=t_prev_hot;  CIP_C5_T_COLD_s_OUT:=t_prev_cold; CIP_C5_T_ALK_s_OUT:=t_prev_alk; CIP_C5_T_ACID_s_OUT:=t_prev_acid; CIP_C5_T_PUMP_s_OUT:=t_prev_pump; CIP_C5_T_DRAIN_s_OUT:=t_prev_drain;
           CIP_C5_MixerStage1_OUT:=MB_CIP_Edit_SEL_OUT.8; CIP_C5_MixerStage2_OUT:=MB_CIP_Edit_SEL_OUT.9; CIP_C5_MixerStage3_OUT:=MB_CIP_Edit_SEL_OUT.10;
        6: CIP_C6_T_HOT_s_OUT:=t_prev_hot;  CIP_C6_T_COLD_s_OUT:=t_prev_cold; CIP_C6_T_ALK_s_OUT:=t_prev_alk; CIP_C6_T_ACID_s_OUT:=t_prev_acid; CIP_C6_T_PUMP_s_OUT:=t_prev_pump; CIP_C6_T_DRAIN_s_OUT:=t_prev_drain;
           CIP_C6_MixerStage1_OUT:=MB_CIP_Edit_SEL_OUT.8; CIP_C6_MixerStage2_OUT:=MB_CIP_Edit_SEL_OUT.9; CIP_C6_MixerStage3_OUT:=MB_CIP_Edit_SEL_OUT.10;
        7: CIP_C7_T_HOT_s_OUT:=t_prev_hot;  CIP_C7_T_COLD_s_OUT:=t_prev_cold; CIP_C7_T_ALK_s_OUT:=t_prev_alk; CIP_C7_T_ACID_s_OUT:=t_prev_acid; CIP_C7_T_PUMP_s_OUT:=t_prev_pump; CIP_C7_T_DRAIN_s_OUT:=t_prev_drain;
           CIP_C7_MixerStage1_OUT:=MB_CIP_Edit_SEL_OUT.8; CIP_C7_MixerStage2_OUT:=MB_CIP_Edit_SEL_OUT.9; CIP_C7_MixerStage3_OUT:=MB_CIP_Edit_SEL_OUT.10;
        END_CASE;
        dirty := FALSE;
    END_IF;
END_IF;

// Маски режимов (569): показать текущую маску и при изменении сохранить в *_OUT
CASE modeSelBits OF
 1: MB_CIP_Edit_MASK_OUT := CIP_ModeMask_Full_IN;
 2: MB_CIP_Edit_MASK_OUT := CIP_ModeMask_Alk_IN;
 3: MB_CIP_Edit_MASK_OUT := CIP_ModeMask_Acid_IN;
 4: MB_CIP_Edit_MASK_OUT := CIP_ModeMask_Rinse_IN;
END_CASE;

IF MB_CIP_Edit_MASK_IN <> MB_CIP_Edit_MASK_OUT THEN
    // ограничим до 7 бит арифметикой
    mask_prev := MB_CIP_Edit_MASK_IN MOD 128;
    CASE modeSelBits OF
      1: CIP_ModeMask_Full_OUT  := mask_prev;
      2: CIP_ModeMask_Alk_OUT   := mask_prev;
      3: CIP_ModeMask_Acid_OUT  := mask_prev;
      4: CIP_ModeMask_Rinse_OUT := mask_prev;
    END_CASE;
    MB_CIP_Edit_MASK_OUT := mask_prev;
END_IF;

// ===================== ВЫБОР РЕЖИМА =====================
runReqAny := CIP_Full_RunReq OR CIP_Alk_RunReq OR CIP_Acid_RunReq OR CIP_Rinse_RunReq;
IF CIP_Full_RunReq THEN
    modeChosen := 1;
ELSIF CIP_Alk_RunReq THEN
    modeChosen := 2;
ELSIF CIP_Acid_RunReq THEN
    modeChosen := 3;
ELSIF CIP_Rinse_RunReq THEN
    modeChosen := 4;
ELSE
    modeChosen := 0;
END_IF;
ActiveModeCode := modeChosen;

// ===================== АВАРИЙНЫЕ СТОПЫ =====================
IF ALM_NoWater OR CMD_Stop THEN
    CIP_Valve_Cold_ON := FALSE; CIP_Valve_Hot_ON := FALSE;
    CIP_Valve_Alk_ON  := FALSE; CIP_Valve_Acid_ON := FALSE;
    CIP_Pump_ON := FALSE; CIP_DrainValve_ON := FALSE; CIP_Mixer_ON := FALSE;

    StageMask_CIP := 0; Mode_ACTIVE := FALSE;
    ActiveCycleNo := 0; ActiveStageNo := 0;
    state := 0; stage := 0; curIdx := 0; cyclesCount := 0;
    t_stage := 0; t_stopDrain := 0;
ELSE

// ===================== МАШИНА СОСТОЯНИЙ =====================
CASE state OF

// -------- 0) IDLE --------
0:
    CIP_Valve_Cold_ON := FALSE; CIP_Valve_Hot_ON := FALSE;
    CIP_Valve_Alk_ON  := FALSE; CIP_Valve_Acid_ON := FALSE;
    CIP_Pump_ON := FALSE; CIP_DrainValve_ON := FALSE; CIP_Mixer_ON := FALSE;
    StageMask_CIP := 0; Mode_ACTIVE := FALSE;
    ActiveStageNo := 0; ActiveCycleNo := 0;

    IF runReqAny AND (modeChosen <> 0) THEN
        // Выбрать маску режима и ограничить до 7 бит (MOD 128)
        IF modeChosen = 1 THEN mask_prev := CIP_ModeMask_Full_IN MOD 128; END_IF;
        IF modeChosen = 2 THEN mask_prev := CIP_ModeMask_Alk_IN  MOD 128; END_IF;
        IF modeChosen = 3 THEN mask_prev := CIP_ModeMask_Acid_IN MOD 128; END_IF;
        IF modeChosen = 4 THEN mask_prev := CIP_ModeMask_Rinse_IN MOD 128; END_IF;

        // Собрать очередь циклов (арифметической проверкой битов)
        cyclesQueue1 := 0; cyclesQueue2 := 0; cyclesQueue3 := 0; cyclesQueue4 := 0;
        cyclesQueue5 := 0; cyclesQueue6 := 0; cyclesQueue7 := 0;
        cyclesCount := 0;

        IF (mask_prev MOD 2) > 0 THEN cyclesCount := cyclesCount + 1; IF cyclesCount=1 THEN cyclesQueue1:=1; ELSIF cyclesCount=2 THEN cyclesQueue2:=1; ELSIF cyclesCount=3 THEN cyclesQueue3:=1; ELSIF cyclesCount=4 THEN cyclesQueue4:=1; ELSIF cyclesCount=5 THEN cyclesQueue5:=1; ELSIF cyclesCount=6 THEN cyclesQueue6:=1; ELSE cyclesQueue7:=1; END_IF; END_IF;
        IF ((mask_prev / 2) MOD 2) > 0 THEN cyclesCount := cyclesCount + 1; IF cyclesCount=1 THEN cyclesQueue1:=2; ELSIF cyclesCount=2 THEN cyclesQueue2:=2; ELSIF cyclesCount=3 THEN cyclesQueue3:=2; ELSIF cyclesCount=4 THEN cyclesQueue4:=2; ELSIF cyclesCount=5 THEN cyclesQueue5:=2; ELSIF cyclesCount=6 THEN cyclesQueue6:=2; ELSE cyclesQueue7:=2; END_IF; END_IF;
        IF ((mask_prev / 4) MOD 2) > 0 THEN cyclesCount := cyclesCount + 1; IF cyclesCount=1 THEN cyclesQueue1:=3; ELSIF cyclesCount=2 THEN cyclesQueue2:=3; ELSIF cyclesCount=3 THEN cyclesQueue3:=3; ELSIF cyclesCount=4 THEN cyclesQueue4:=3; ELSIF cyclesCount=5 THEN cyclesQueue5:=3; ELSIF cyclesCount=6 THEN cyclesQueue6:=3; ELSE cyclesQueue7:=3; END_IF; END_IF;
        IF ((mask_prev / 8) MOD 2) > 0 THEN cyclesCount := cyclesCount + 1; IF cyclesCount=1 THEN cyclesQueue1:=4; ELSIF cyclesCount=2 THEN cyclesQueue2:=4; ELSIF cyclesCount=3 THEN cyclesQueue3:=4; ELSIF cyclesCount=4 THEN cyclesQueue4:=4; ELSIF cyclesCount=5 THEN cyclesQueue5:=4; ELSIF cyclesCount=6 THEN cyclesQueue6:=4; ELSE cyclesQueue7:=4; END_IF; END_IF;
        IF ((mask_prev / 16) MOD 2) > 0 THEN cyclesCount := cyclesCount + 1; IF cyclesCount=1 THEN cyclesQueue1:=5; ELSIF cyclesCount=2 THEN cyclesQueue2:=5; ELSIF cyclesCount=3 THEN cyclesQueue3:=5; ELSIF cyclesCount=4 THEN cyclesQueue4:=5; ELSIF cyclesCount=5 THEN cyclesQueue5:=5; ELSIF cyclesCount=6 THEN cyclesQueue6:=5; ELSE cyclesQueue7:=5; END_IF; END_IF;
        IF ((mask_prev / 32) MOD 2) > 0 THEN cyclesCount := cyclesCount + 1; IF cyclesCount=1 THEN cyclesQueue1:=6; ELSIF cyclesCount=2 THEN cyclesQueue2:=6; ELSIF cyclesCount=3 THEN cyclesQueue3:=6; ELSIF cyclesCount=4 THEN cyclesQueue4:=6; ELSIF cyclesCount=5 THEN cyclesQueue5:=6; ELSIF cyclesCount=6 THEN cyclesQueue6:=6; ELSE cyclesQueue7:=6; END_IF; END_IF;
        IF ((mask_prev / 64) MOD 2) > 0 THEN cyclesCount := cyclesCount + 1; IF cyclesCount=1 THEN cyclesQueue1:=7; ELSIF cyclesCount=2 THEN cyclesQueue2:=7; ELSIF cyclesCount=3 THEN cyclesQueue3:=7; ELSIF cyclesCount=4 THEN cyclesQueue4:=7; ELSIF cyclesCount=5 THEN cyclesQueue5:=7; ELSIF cyclesCount=6 THEN cyclesQueue6:=7; ELSE cyclesQueue7:=7; END_IF; END_IF;

        IF cyclesCount > 0 THEN
            curIdx := 1;
            // текущий номер
            ActiveCycleNo := 0;
            IF curIdx = 1 THEN ActiveCycleNo := cyclesQueue1; END_IF;
            IF curIdx = 2 THEN ActiveCycleNo := cyclesQueue2; END_IF;
            IF curIdx = 3 THEN ActiveCycleNo := cyclesQueue3; END_IF;
            IF curIdx = 4 THEN ActiveCycleNo := cyclesQueue4; END_IF;
            IF curIdx = 5 THEN ActiveCycleNo := cyclesQueue5; END_IF;
            IF curIdx = 6 THEN ActiveCycleNo := cyclesQueue6; END_IF;
            IF curIdx = 7 THEN ActiveCycleNo := cyclesQueue7; END_IF;

            // Загрузить уставки цикла
            CASE ActiveCycleNo OF
            1: U_T_HOT:=CIP_C1_T_HOT_s_IN; U_T_COLD:=CIP_C1_T_COLD_s_IN; U_T_ALK:=CIP_C1_T_ALK_s_IN; U_T_ACID:=CIP_C1_T_ACID_s_IN; U_T_PUMP:=CIP_C1_T_PUMP_s_IN; U_T_DRAIN:=CIP_C1_T_DRAIN_s_IN; U_Mix_S1:=CIP_C1_MixerStage1_IN; U_Mix_S2:=CIP_C1_MixerStage2_IN; U_Mix_S3:=CIP_C1_MixerStage3_IN;
            2: U_T_HOT:=CIP_C2_T_HOT_s_IN; U_T_COLD:=CIP_C2_T_COLD_s_IN; U_T_ALK:=CIP_C2_T_ALK_s_IN; U_T_ACID:=CIP_C2_T_ACID_s_IN; U_T_PUMP:=CIP_C2_T_PUMP_s_IN; U_T_DRAIN:=CIP_C2_T_DRAIN_s_IN; U_Mix_S1:=CIP_C2_MixerStage1_IN; U_Mix_S2:=CIP_C2_MixerStage2_IN; U_Mix_S3:=CIP_C2_MixerStage3_IN;
            3: U_T_HOT:=CIP_C3_T_HOT_s_IN; U_T_COLD:=CIP_C3_T_COLD_s_IN; U_T_ALK:=CIP_C3_T_ALK_s_IN; U_T_ACID:=CIP_C3_T_ACID_s_IN; U_T_PUMP:=CIP_C3_T_PUMP_s_IN; U_T_DRAIN:=CIP_C3_T_DRAIN_s_IN; U_Mix_S1:=CIP_C3_MixerStage1_IN; U_Mix_S2:=CIP_C3_MixerStage2_IN; U_Mix_S3:=CIP_C3_MixerStage3_IN;
            4: U_T_HOT:=CIP_C4_T_HOT_s_IN; U_T_COLD:=CIP_C4_T_COLD_s_IN; U_T_ALK:=CIP_C4_T_ALK_s_IN; U_T_ACID:=CIP_C4_T_ACID_s_IN; U_T_PUMP:=CIP_C4_T_PUMP_s_IN; U_T_DRAIN:=CIP_C4_T_DRAIN_s_IN; U_Mix_S1:=CIP_C4_MixerStage1_IN; U_Mix_S2:=CIP_C4_MixerStage2_IN; U_Mix_S3:=CIP_C4_MixerStage3_IN;
            5: U_T_HOT:=CIP_C5_T_HOT_s_IN; U_T_COLD:=CIP_C5_T_COLD_s_IN; U_T_ALK:=CIP_C5_T_ALK_s_IN; U_T_ACID:=CIP_C5_T_ACID_s_IN; U_T_PUMP:=CIP_C5_T_PUMP_s_IN; U_T_DRAIN:=CIP_C5_T_DRAIN_s_IN; U_Mix_S1:=CIP_C5_MixerStage1_IN; U_Mix_S2:=CIP_C5_MixerStage2_IN; U_Mix_S3:=CIP_C5_MixerStage3_IN;
            6: U_T_HOT:=CIP_C6_T_HOT_s_IN; U_T_COLD:=CIP_C6_T_COLD_s_IN; U_T_ALK:=CIP_C6_T_ALK_s_IN; U_T_ACID:=CIP_C6_T_ACID_s_IN; U_T_PUMP:=CIP_C6_T_PUMP_s_IN; U_T_DRAIN:=CIP_C6_T_DRAIN_s_IN; U_Mix_S1:=CIP_C6_MixerStage1_IN; U_Mix_S2:=CIP_C6_MixerStage2_IN; U_Mix_S3:=CIP_C6_MixerStage3_IN;
            7: U_T_HOT:=CIP_C7_T_HOT_s_IN; U_T_COLD:=CIP_C7_T_COLD_s_IN; U_T_ALK:=CIP_C7_T_ALK_s_IN; U_T_ACID:=CIP_C7_T_ACID_s_IN; U_T_PUMP:=CIP_C7_T_PUMP_s_IN; U_T_DRAIN:=CIP_C7_T_DRAIN_s_IN; U_Mix_S1:=CIP_C7_MixerStage1_IN; U_Mix_S2:=CIP_C7_MixerStage2_IN; U_Mix_S3:=CIP_C7_MixerStage3_IN;
            ELSE
                U_T_HOT:=0; U_T_COLD:=0; U_T_ALK:=0; U_T_ACID:=0; U_T_PUMP:=0; U_T_DRAIN:=0; U_Mix_S1:=FALSE; U_Mix_S2:=FALSE; U_Mix_S3:=FALSE;
            END_CASE;

            // Конфликт ALK+ACID
            alk_en  := U_T_ALK  > 0;
            acid_en := U_T_ACID > 0;
            IF alk_en AND acid_en THEN
                IF CIP_ChemConflictPolicy_IN = 0 THEN
                    U_T_ALK := 0; U_T_ACID := 0;
                ELSIF CIP_ChemConflictPolicy_IN = 1 THEN
                    U_T_ACID := 0;
                ELSE
                    U_T_ALK := 0;
                END_IF;
            END_IF;

            // Старт этапа 1
            t_stage := 0; stage := 1; Mode_ACTIVE := TRUE; ActiveStageNo := 1; state := 1;
        END_IF;
    END_IF;

// -------- 1) RUN --------
1:
    IF NOT runReqAny THEN
        CIP_Valve_Cold_ON := FALSE; CIP_Valve_Hot_ON := FALSE;
        CIP_Valve_Alk_ON  := FALSE; CIP_Valve_Acid_ON := FALSE;
        CIP_Pump_ON := FALSE; CIP_Mixer_ON := FALSE;
        CIP_DrainValve_ON := TRUE;
        StageMask_CIP := 0; ActiveStageNo := 0;
        t_stopDrain := 0; state := 2;
    ELSE
        IF stage = 1 THEN
            // ЭТАП 1 — набор
            StageMask_CIP := 1;
            CIP_Valve_Hot_ON  := (U_T_HOT  > 0) AND (t_stage < U_T_HOT);
            CIP_Valve_Cold_ON := (U_T_COLD > 0) AND (t_stage < U_T_COLD);
            CIP_Valve_Alk_ON  := (U_T_ALK  > 0) AND (t_stage < U_T_ALK);
            CIP_Valve_Acid_ON := (U_T_ACID > 0) AND (t_stage < U_T_ACID);
            CIP_Pump_ON := FALSE; CIP_DrainValve_ON := FALSE; CIP_Mixer_ON := U_Mix_S1;

            // max для перехода
            t1_max := U_T_HOT;
            IF U_T_COLD > t1_max THEN t1_max := U_T_COLD; END_IF;
            IF U_T_ALK  > t1_max THEN t1_max := U_T_ALK;  END_IF;
            IF U_T_ACID > t1_max THEN t1_max := U_T_ACID; END_IF;

            IF t_stage >= t1_max THEN
                CIP_Valve_Hot_ON := FALSE; CIP_Valve_Cold_ON := FALSE;
                CIP_Valve_Alk_ON := FALSE; CIP_Valve_Acid_ON := FALSE;
                t_stage := 0; stage := 2; ActiveStageNo := 2;
            END_IF;

        ELSIF stage = 2 THEN
            // ЭТАП 2 — циркуляция
            StageMask_CIP := 2;
            CIP_Valve_Hot_ON := FALSE; CIP_Valve_Cold_ON := FALSE;
            CIP_Valve_Alk_ON := FALSE; CIP_Valve_Acid_ON := FALSE;
            CIP_DrainValve_ON := FALSE;
            CIP_Pump_ON := (U_T_PUMP > 0) AND (t_stage < U_T_PUMP);
            CIP_Mixer_ON := U_Mix_S2;

            IF t_stage >= U_T_PUMP THEN
                CIP_Pump_ON := FALSE;
                t_stage := 0; stage := 3; ActiveStageNo := 3;
            END_IF;

        ELSIF stage = 3 THEN
            // ЭТАП 3 — слив
            StageMask_CIP := 4;
            CIP_Valve_Hot_ON := FALSE; CIP_Valve_Cold_ON := FALSE;
            CIP_Valve_Alk_ON := FALSE; CIP_Valve_Acid_ON := FALSE;
            CIP_Pump_ON := FALSE; CIP_Mixer_ON := U_Mix_S3;
            CIP_DrainValve_ON := (U_T_DRAIN > 0) AND (t_stage < U_T_DRAIN);

            IF t_stage >= U_T_DRAIN THEN
                CIP_DrainValve_ON := FALSE;

                // Следующий цикл
                curIdx := curIdx + 1;
                IF curIdx > cyclesCount THEN
                    Mode_ACTIVE := FALSE; ActiveCycleNo := 0; ActiveStageNo := 0;
                    state := 0; stage := 0; t_stage := 0; StageMask_CIP := 0;
                ELSE
                    ActiveCycleNo := 0;
                    IF curIdx = 1 THEN ActiveCycleNo := cyclesQueue1; END_IF;
                    IF curIdx = 2 THEN ActiveCycleNo := cyclesQueue2; END_IF;
                    IF curIdx = 3 THEN ActiveCycleNo := cyclesQueue3; END_IF;
                    IF curIdx = 4 THEN ActiveCycleNo := cyclesQueue4; END_IF;
                    IF curIdx = 5 THEN ActiveCycleNo := cyclesQueue5; END_IF;
                    IF curIdx = 6 THEN ActiveCycleNo := cyclesQueue6; END_IF;
                    IF curIdx = 7 THEN ActiveCycleNo := cyclesQueue7; END_IF;

                    CASE ActiveCycleNo OF
                    1: U_T_HOT:=CIP_C1_T_HOT_s_IN; U_T_COLD:=CIP_C1_T_COLD_s_IN; U_T_ALK:=CIP_C1_T_ALK_s_IN; U_T_ACID:=CIP_C1_T_ACID_s_IN; U_T_PUMP:=CIP_C1_T_PUMP_s_IN; U_T_DRAIN:=CIP_C1_T_DRAIN_s_IN; U_Mix_S1:=CIP_C1_MixerStage1_IN; U_Mix_S2:=CIP_C1_MixerStage2_IN; U_Mix_S3:=CIP_C1_MixerStage3_IN;
                    2: U_T_HOT:=CIP_C2_T_HOT_s_IN; U_T_COLD:=CIP_C2_T_COLD_s_IN; U_T_ALK:=CIP_C2_T_ALK_s_IN; U_T_ACID:=CIP_C2_T_ACID_s_IN; U_T_PUMP:=CIP_C2_T_PUMP_s_IN; U_T_DRAIN:=CIP_C2_T_DRAIN_s_IN; U_Mix_S1:=CIP_C2_MixerStage1_IN; U_Mix_S2:=CIP_C2_MixerStage2_IN; U_Mix_S3:=CIP_C2_MixerStage3_IN;
                    3: U_T_HOT:=CIP_C3_T_HOT_s_IN; U_T_COLD:=CIP_C3_T_COLD_s_IN; U_T_ALK:=CIP_C3_T_ALK_s_IN; U_T_ACID:=CIP_C3_T_ACID_s_IN; U_T_PUMP:=CIP_C3_T_PUMP_s_IN; U_T_DRAIN:=CIP_C3_T_DRAIN_s_IN; U_Mix_S1:=CIP_C3_MixerStage1_IN; U_Mix_S2:=CIP_C3_MixerStage2_IN; U_Mix_S3:=CIP_C3_MixerStage3_IN;
                    4: U_T_HOT:=CIP_C4_T_HOT_s_IN; U_T_COLD:=CIP_C4_T_COLD_s_IN; U_T_ALK:=CIP_C4_T_ALK_s_IN; U_T_ACID:=CIP_C4_T_ACID_s_IN; U_T_PUMP:=CIP_C4_T_PUMP_s_IN; U_T_DRAIN:=CIP_C4_T_DRAIN_s_IN; U_Mix_S1:=CIP_C4_MixerStage1_IN; U_Mix_S2:=CIP_C4_MixerStage2_IN; U_Mix_S3:=CIP_C4_MixerStage3_IN;
                    5: U_T_HOT:=CIP_C5_T_HOT_s_IN; U_T_COLD:=CIP_C5_T_COLD_s_IN; U_T_ALK:=CIP_C5_T_ALK_s_IN; U_T_ACID:=CIP_C5_T_ACID_s_IN; U_T_PUMP:=CIP_C5_T_PUMP_s_IN; U_T_DRAIN:=CIP_C5_T_DRAIN_s_IN; U_Mix_S1:=CIP_C5_MixerStage1_IN; U_Mix_S2:=CIP_C5_MixerStage2_IN; U_Mix_S3:=CIP_C5_MixerStage3_IN;
                    6: U_T_HOT:=CIP_C6_T_HOT_s_IN; U_T_COLD:=CIP_C6_T_COLD_s_IN; U_T_ALK:=CIP_C6_T_ALK_s_IN; U_T_ACID:=CIP_C6_T_ACID_s_IN; U_T_PUMP:=CIP_C6_T_PUMP_s_IN; U_T_DRAIN:=CIP_C6_T_DRAIN_s_IN; U_Mix_S1:=CIP_C6_MixerStage1_IN; U_Mix_S2:=CIP_C6_MixerStage2_IN; U_Mix_S3:=CIP_C6_MixerStage3_IN;
                    7: U_T_HOT:=CIP_C7_T_HOT_s_IN; U_T_COLD:=CIP_C7_T_COLD_s_IN; U_T_ALK:=CIP_C7_T_ALK_s_IN; U_T_ACID:=CIP_C7_T_ACID_s_IN; U_T_PUMP:=CIP_C7_T_PUMP_s_IN; U_T_DRAIN:=CIP_C7_T_DRAIN_s_IN; U_Mix_S1:=CIP_C7_MixerStage1_IN; U_Mix_S2:=CIP_C7_MixerStage2_IN; U_Mix_S3:=CIP_C7_MixerStage3_IN;
                    ELSE
                        U_T_HOT:=0; U_T_COLD:=0; U_T_ALK:=0; U_T_ACID:=0; U_T_PUMP:=0; U_T_DRAIN:=0; U_Mix_S1:=FALSE; U_Mix_S2:=FALSE; U_Mix_S3:=FALSE;
                    END_CASE;

                    // Конфликт ALK+ACID
                    alk_en  := U_T_ALK  > 0;
                    acid_en := U_T_ACID > 0;
                    IF alk_en AND acid_en THEN
                        IF CIP_ChemConflictPolicy_IN = 0 THEN
                            U_T_ALK := 0; U_T_ACID := 0;
                        ELSIF CIP_ChemConflictPolicy_IN = 1 THEN
                            U_T_ACID := 0;
                        ELSE
                            U_T_ALK := 0;
                        END_IF;
                    END_IF;

                    t_stage := 0; stage := 1; ActiveStageNo := 1;
                END_IF;
            END_IF;
        ELSE
            state := 0; stage := 0; Mode_ACTIVE := FALSE; StageMask_CIP := 0;
        END_IF;
    END_IF;

// -------- 2) STOPPING --------
2:
    CIP_Valve_Cold_ON := FALSE; CIP_Valve_Hot_ON := FALSE;
    CIP_Valve_Alk_ON  := FALSE; CIP_Valve_Acid_ON := FALSE;
    CIP_Pump_ON := FALSE; CIP_Mixer_ON := FALSE;
    CIP_DrainValve_ON := TRUE;
    StageMask_CIP := 0; Mode_ACTIVE := TRUE;

    IF t_stopDrain >= CIP_DrainOnStopSec_IN THEN
        CIP_DrainValve_ON := FALSE;
        t_stopDrain := 0;
        IF runReqAny AND (modeChosen <> 0) THEN
            state := 0;
        ELSE
            Mode_ACTIVE := FALSE;
            state := 0; stage := 0; t_stage := 0; ActiveCycleNo := 0; ActiveStageNo := 0; StageMask_CIP := 0;
        END_IF;
    END_IF;

ELSE
    // (нет)
END_CASE;

END_IF; // аварии/стоп

// Текущий таймер этапа на выход
Timer_StageSec := t_stage;

END_FUNCTION_BLOCK