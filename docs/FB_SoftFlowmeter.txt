FUNCTION_BLOCK FB_SoftFlowmeter
VAR_INPUT
    Enable     : BOOL;   // разрешение интегратора
    Seconds_UD : UDINT;  // секундный тик (монотонный)
    PumpOn     : BOOL;   // насос работает
    Rate_Lps   : REAL;   // производительность, л/с
    Reset      : BOOL;   // сброс накопления
END_VAR

VAR_OUTPUT
    FlowAbs_L  : REAL;   // накопленный объём, л (абсолют)
    Delta_L    : REAL;   // прирост за последний шаг, л
END_VAR

VAR
    init_done  : BOOL  := FALSE;
    lastSec_UD : UDINT := 0;
    accum_L    : REAL  := 0.0;
    secDiff_UD : UDINT := 0;    // <-- выносим сюда
END_VAR

// --- инициализация ---
IF NOT init_done THEN
    lastSec_UD := Seconds_UD;
    accum_L    := 0.0;
    FlowAbs_L  := 0.0;
    Delta_L    := 0.0;
    init_done  := TRUE;
END_IF;

// --- сброс ---
IF Reset THEN
    accum_L   := 0.0;
    FlowAbs_L := 0.0;
    Delta_L   := 0.0;
END_IF;

// --- по умолчанию прирост = 0 ---
Delta_L := 0.0;

// --- основной цикл интеграции ---
IF Enable THEN
    IF Seconds_UD <> lastSec_UD THEN
        secDiff_UD := Seconds_UD - lastSec_UD;
        IF secDiff_UD > 10 THEN secDiff_UD := 10; END_IF;   // защита от «рывка»
        lastSec_UD := Seconds_UD;

        IF PumpOn THEN
            Delta_L := Rate_Lps * UDINT_TO_REAL(secDiff_UD); // правильное приведение
            IF Delta_L < 0.0 THEN Delta_L := 0.0; END_IF;
            accum_L := accum_L + Delta_L;
        END_IF;
    END_IF;
END_IF;

// защита от отрицательных
IF accum_L < 0.0 THEN accum_L := 0.0; END_IF;
FlowAbs_L := accum_L;

END_FUNCTION_BLOCK
