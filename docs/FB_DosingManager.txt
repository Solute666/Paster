FUNCTION_BLOCK FB_DosingManager
VAR_INPUT
    EN_Continuous        : BOOL;  // запрос непрерывного розлива (уровень)
    EN_Portion           : BOOL;  // запрос дозированного розлива (уровень)

    PAR_UseGunSensor     : BOOL;  // ждать сигнал "пистолет на месте"
    GunSensor            : BOOL;  // TRUE = пистолет на месте

    PAR_UsePortionButton : BOOL;  // использовать внешнюю кнопку порции
    PortionButton        : BOOL;  // TRUE = кнопка нажата

    SP_DoseVolume        : REAL;  // объём дозы, л
    FlowMeter            : REAL;  // ОБЩИЙ/АБСОЛЮТНЫЙ накопленный объём, л (счётчик)
END_VAR

VAR_OUTPUT
    FillPump_ON  : BOOL;  // команда на насос розлива (DO5)
    PortionDone  : BOOL;  // завершение дозы (импульсом)
END_VAR

VAR
    dosingActive      : BOOL := FALSE;  // в процессе дозирования
    flowBaseAtStart   : REAL := 0.0;    // база счётчика на старте дозы
    doseAccum         : REAL := 0.0;    // дельта объёма с начала дозы
    init_done         : BOOL := FALSE;
    canStart          : BOOL := FALSE;
END_VAR

// --- одноразовая инициализация ---
IF NOT init_done THEN
    FillPump_ON := FALSE;
    PortionDone := FALSE;
    dosingActive := FALSE;
    flowBaseAtStart := 0.0;
    doseAccum := 0.0;
    init_done := TRUE;
END_IF;

// сбрасываем "готово" по умолчанию (если нужна защёлка — реализовать снаружи)
PortionDone := FALSE;

// ===== ПОРЦИОННЫЙ РЕЖИМ (имеет приоритет над непрерывным) =====
IF EN_Portion THEN

    IF NOT dosingActive THEN
        // проверяем условия старта
        canStart := TRUE;

        IF PAR_UsePortionButton THEN
            canStart := canStart AND PortionButton;
        END_IF;

        IF PAR_UseGunSensor THEN
            canStart := canStart AND GunSensor;
        END_IF;

        IF canStart THEN
            dosingActive := TRUE;
            flowBaseAtStart := FlowMeter;   // запоминаем базу абсолютного счётчика
            doseAccum := 0.0;
            FillPump_ON := TRUE;
        ELSE
            FillPump_ON := FALSE;
        END_IF;

    ELSE
        // доза идёт
        doseAccum := FlowMeter - flowBaseAtStart;
        IF doseAccum < 0.0 THEN
            // защита от возможного переполнения/обнуления счётчика
            flowBaseAtStart := FlowMeter;
            doseAccum := 0.0;
        END_IF;

        IF doseAccum >= SP_DoseVolume THEN
            // доза набрана — корректная остановка, флаг завершения
            FillPump_ON := FALSE;
            PortionDone := TRUE;
            dosingActive := FALSE;
            doseAccum := 0.0;

        ELSE
            // при снятом пистолете — пауза насоса, но дозирование не сбрасываем
            IF PAR_UseGunSensor AND (NOT GunSensor) THEN
                FillPump_ON := FALSE;
            ELSE
                FillPump_ON := TRUE;
            END_IF;
        END_IF;
    END_IF;

ELSE
    // порционный режим выключен — аварийный/принудительный выход из дозы
    dosingActive := FALSE;
    doseAccum := 0.0;
END_IF;

// ===== НЕПРЕРЫВНЫЙ РЕЖИМ (работает, только когда порционный не активен) =====
IF (NOT EN_Portion) AND (NOT dosingActive) THEN
    IF EN_Continuous THEN
        IF PAR_UseGunSensor THEN
            FillPump_ON := GunSensor;   // только при "пистолет на месте"
        ELSE
            FillPump_ON := TRUE;
        END_IF;
    ELSE
        FillPump_ON := FALSE;
    END_IF;
END_IF;

END_FUNCTION_BLOCK
