FUNCTION_BLOCK FB_PasteurManager
VAR_INPUT
    // ===== Запрос режима (уровень) =====
    RunReq          : BOOL;   // 1 = цикл активен, 0 = останов

    // ===== Режим/уставки =====
    RecipeMode      : BOOL;   // Поэтапный (рецептурный) режим
    SP_HeatTemp     : REAL;   // Целевая температура нагрева, °C
    SP_HeatTime     : UDINT;  // Время плавного разгона, мин (0 = нет)  // (пока не используется)
    SP_SmoothTemp   : REAL;   // (резерв)
    SP_SmoothDiff   : REAL;   // Дифф. рубашки при плавном нагреве, °C  // (исп. в защите холода)
    SP_HoldTime     : UDINT;  // Длительность выдержки, с
    SP_HoldDiff     : REAL;   // Дифференциал выдержки, °C
    SP_CoolTemp     : REAL;   // Температура охлаждения, °C
    PAR_UsePID      : BOOL;   // 1=PID, 0=гистерезис (здесь не влияет, оставлено для совместимости)

    // ===== Измерения =====
    PV_TempProduct  : REAL;   // Т текущая продукта, °C
    PV_TempJacket   : REAL;   // Т текущая рубашки, °C

    // ===== Команды сервиса (опциональные уровни) =====
    CMD_Stop        : BOOL;   // Немедленный стоп (авария/стоп-кнопка)
    CMD_SkipHeat    : BOOL;   // Пропустить нагрев (опционально)
    CMD_Resume      : BOOL;   // Продолжить из паузы 99 (опционально)
END_VAR

VAR_OUTPUT
    // Команды в актуатор/температурный менеджер
    CircPump_ON       : BOOL;  // → DO2_CircPump
    Mixer_ON          : BOOL;  // → DO3_MixerFwd (реверс не используется)
    CoolingValve_ON   : BOOL;  // → DO1_ValveCold
    HeatingPowerReq   : BOOL;  // EN_Heat: 1=разрешить нагрев, 0=выкл (для TemperatureManager)

    // Отображение стадий
    StageMask_Pasteur : UDINT; // бит0..бит5: HEAT,HOLD,COOL,MIX/ALIGN,STORE,DONE
END_VAR

VAR
    init_done        : BOOL  := FALSE;

    // Стадии: 0=IDLE; 1=HEAT; 2=HOLD; 3=COOL; 4=MIX/EQUAL; 5=STORE; 6=DONE; 99=PAUSE
    stage            : UDINT := 0;

    holdSec          : UDINT := 0;   // накопленное время выдержки, с (вызов ФБ 1 Гц)
    holdDone         : BOOL  := FALSE;

    mixSec           : UDINT := 0;   // время вымешивания/выравнивания, с
    storageMode      : BOOL  := FALSE;
END_VAR

// ---------- Инициализация ----------
IF NOT init_done THEN
    stage := 0; // IDLE
    CircPump_ON := FALSE;
    Mixer_ON := FALSE;
    HeatingPowerReq := FALSE;     // нагрев запрещён
    CoolingValve_ON := FALSE;
    StageMask_Pasteur := 0;

    holdSec := 0; holdDone := FALSE;
    mixSec := 0;
    storageMode := FALSE;

    init_done := TRUE;
END_IF;

// ---------- Общий стоп/сброс ----------
IF (NOT RunReq) OR CMD_Stop THEN
    // Безопасное выключение
    CircPump_ON := FALSE;
    Mixer_ON := FALSE;
    HeatingPowerReq := FALSE;
    CoolingValve_ON := FALSE;
    StageMask_Pasteur := 0;

    // Сброс внутреннего состояния
    holdSec := 0; holdDone := FALSE;
    mixSec := 0;
    storageMode := FALSE;

    stage := 0; // IDLE
ELSE
    // ---------- Обнулить маску этапов на этот цикл обновления ----------
    StageMask_Pasteur := 0;

    // ---------- Переход из IDLE ----------
    IF stage = 0 THEN
        IF CMD_SkipHeat THEN
            // Пропуск нагрева → сразу выдержка
            stage := 2;                     // HOLD
            holdSec := 0; holdDone := FALSE;
            CircPump_ON := TRUE;
            Mixer_ON := TRUE;
            HeatingPowerReq := TRUE;        // разрешаем нагрев для удержания SP
        ELSE
            stage := 1;                     // HEAT
            CircPump_ON := TRUE;
            Mixer_ON := TRUE;
            HeatingPowerReq := TRUE;        // разрешаем нагрев
        END_IF;
    END_IF;

    // ---------- Этап 1: Нагрев ----------
    IF stage = 1 THEN
        StageMask_Pasteur.0 := TRUE;

        // Разрешение нагрева, пока не достигнута SP_HeatTemp
        IF PV_TempProduct >= SP_HeatTemp THEN
            HeatingPowerReq := FALSE;       // температура достигнута, выключаем нагрев
            stage := 2;                     // → HOLD
            holdSec := 0;
        ELSE
            HeatingPowerReq := TRUE;        // продолжать нагрев
        END_IF;
    END_IF;

    // ---------- Этап 2: Выдержка ----------
    IF stage = 2 THEN
        StageMask_Pasteur.1 := TRUE;

        // Двухпозиционная поддержка вокруг SP_HeatTemp
        IF PV_TempProduct < (SP_HeatTemp - SP_HoldDiff) THEN
            HeatingPowerReq := TRUE;
        ELSIF PV_TempProduct >= SP_HeatTemp THEN
            HeatingPowerReq := FALSE;
        END_IF;

        // Учёт времени выдержки
        IF NOT holdDone THEN
            holdSec := holdSec + 1;                    // 1 Гц
            IF holdSec >= SP_HoldTime THEN
                holdDone := TRUE;
                IF RecipeMode AND (NOT CMD_Resume) THEN
                    HeatingPowerReq := FALSE;
                    stage := 99;                        // Пауза, ждём Resume
                ELSE
                    stage := 3;                         // → Охлаждение
                END_IF;
            END_IF;
        END_IF;
    END_IF;

    // ---------- Этап 99: Пауза (рецептурный режим) ----------
    IF stage = 99 THEN
        StageMask_Pasteur.1 := TRUE;                   // визуально «выдержка»

        // Поддержка температуры как в HOLD
        IF PV_TempProduct < (SP_HeatTemp - SP_HoldDiff) THEN
            HeatingPowerReq := TRUE;
        ELSIF PV_TempProduct >= SP_HeatTemp THEN
            HeatingPowerReq := FALSE;
        END_IF;

        // Продолжить только при команде Resume
        IF CMD_Resume THEN
            HeatingPowerReq := FALSE;
            stage := 3;                                 // → Охлаждение
        END_IF;
    END_IF;

    // ---------- Этап 3: Охлаждение ----------
    IF stage = 3 THEN
        StageMask_Pasteur.2 := TRUE;

        HeatingPowerReq := FALSE;       // нагрев запрещён
        CoolingValve_ON  := TRUE;       // открыть холод

        IF PV_TempProduct <= SP_CoolTemp THEN
            CoolingValve_ON := FALSE;
            stage := 4;                 // → выравнивание
            mixSec := 0;
        ELSE
            // защита от переохлаждения рубашки
            IF PV_TempJacket <= (SP_CoolTemp - SP_SmoothDiff) THEN
                CoolingValve_ON := FALSE;
            ELSE
                CoolingValve_ON := TRUE;
            END_IF;
        END_IF;
    END_IF;

    // ---------- Этап 4: Выравнивание/вымешивание ----------
    IF stage = 4 THEN
        StageMask_Pasteur.3 := TRUE;

        CoolingValve_ON := FALSE;

        // Разрешим лёгкий подогрев, если рубашка ниже SP_CoolTemp
        HeatingPowerReq := (PV_TempJacket < SP_CoolTemp);

        CircPump_ON := TRUE;
        Mixer_ON := TRUE;

        IF mixSec < (5 * 60) THEN
            mixSec := mixSec + 1;     // 1 Гц
        ELSE
            IF storageMode THEN
                stage := 5;           // → хранение
            ELSE
                stage := 6;           // → завершение
            END_IF;
        END_IF;
    END_IF;

    // ---------- Этап 5: Хранение ----------
    IF stage = 5 THEN
        StageMask_Pasteur.4 := TRUE;

        // Дельта вокруг SP_CoolTemp: ниже — греть разрешаем, выше — охлаждаем
        IF PV_TempProduct < (SP_CoolTemp - 1.0) THEN
            HeatingPowerReq := TRUE;
            CoolingValve_ON := FALSE;
        ELSIF PV_TempProduct > (SP_CoolTemp + 1.0) THEN
            HeatingPowerReq := FALSE;
            CoolingValve_ON := TRUE;
        ELSE
            HeatingPowerReq := FALSE;
            CoolingValve_ON := FALSE;
        END_IF;

        Mixer_ON := TRUE;
        CircPump_ON := TRUE;
        // Выход из хранения — снятием RunReq или аварией
    END_IF;

    // ---------- Этап 6: Завершение ----------
    IF stage = 6 THEN
        StageMask_Pasteur.5 := TRUE;   // «завершено»
        HeatingPowerReq := FALSE;
        CoolingValve_ON := FALSE;
        CircPump_ON := FALSE;
        Mixer_ON := FALSE;
        // Держим «завершено» пока не снимут RunReq
    END_IF;

END_IF;

END_FUNCTION_BLOCK
