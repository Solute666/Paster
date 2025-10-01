(*
  FB_TemperatureManager_v2
  - Типы: BOOL / UDINT / REAL (совместимо с owenLogic).
  - Пастеризатор даёт: EN_Heat (разрешение нагрева) и SP_TempTarget (уставка, °C).
  - В зависимости от PAR_UsePID:
      * TRUE  → ПИД по (SP_TempTarget, PV_TempProduct), выход 0..100 %, далее ШИМ + каскад групп.
      * FALSE → Гистерезис по PV/SP (двоичный: 0/100 %), далее тот же ШИМ + каскад групп.
  - ШИМ тайм-пропорциональный с периодом PAR_PWM_Period_s (SSR: 1..2 c; контактор: 10..30 c).
  - Фильтрация температур: IIR 1-го порядка (alpha из PAR_FilterAlpha_x1000: 0..1000 → 0..1).
  - Защита по ΔT рубашка–продукт: если превышена SmoothDiffGuard, мощность ограничивается.
*)

FUNCTION_BLOCK FB_TemperatureManager_v2

VAR_INPUT
    // Сырые (уже преобразованные в MAIN) температуры, °C:
    PV_TempProduct_Raw  : REAL;       // продукт
    PV_TempJacket_Raw   : REAL;       // рубашка

    // Режим работы:
    PAR_UsePID          : BOOL;       // TRUE: ПИД, FALSE: гистерезис

    // Управление от пастеризатора:
    EN_Heat             : BOOL;       // разрешение нагрева (стадии HEAT/HOLD)
    SP_TempTarget       : REAL;       // целевая T (°C) для ПИД/гистерезиса

    // Время/ШИМ:
    Seconds_UD          : UDINT;      // секундный тик из MAIN
    PAR_PWM_Period_s    : UDINT;      // период ШИМ, с (SSR 1..2; контактор 10..30)

    // Каскад групп (пороги включения в %, 0..100):
    PAR_G2_StartPct     : REAL;       // дефолт 60 (%)
    PAR_G3_StartPct     : REAL;       // дефолт 85 (%)

    // Разрешение групп (из MAIN):
    PAR_HeaterGroup2Enabled : BOOL;   // TRUE = разрешить DO_Heater2
    PAR_HeaterGroup3Enabled : BOOL;   // TRUE = разрешить DO_Heater3

    // Фильтр температур:
    PAR_FilterAlpha_x1000 : UDINT;    // 0..1000 → 0.000..1.000 (0=без фильтра)

    // ===== Параметры гистерезиса =====
    HYST_OnBelow        : REAL;       // включать, если PV ≤ SP − OnBelow (°C)
    HYST_OffEarly       : REAL;       // выключать, если PV ≥ SP − OffEarly (°C)
    HYST_MinOn_s        : UDINT;      // минимальное «вкл», c
    HYST_MinOff_s       : UDINT;      // минимальное «выкл», c
    HYST_Equilize_s     : UDINT;      // пауза уравновешивания после выкл, c
    SmoothDiffGuard     : REAL;       // макс. допустимая ΔT рубашка–продукт, °C
    PAR_MaxDutyPct_JacketGuard : REAL; // макс. % при превышении ΔT (например 20)

    // ===== Параметры ПИД =====
    PAR_PID_Kp          : REAL;       // безразмерный
    PAR_PID_Ti          : REAL;       // сек (0 = без интеграла)
    PAR_PID_Td          : REAL;       // сек (0 = без дифференциала)
END_VAR

VAR_OUTPUT
    // Команды на силовую часть:
    DO_Heater1_Cmd      : BOOL;       // группа 1 (DO6)
    DO_Heater2_Cmd      : BOOL;       // группа 2 (DO7)
    DO_Heater3_Cmd      : BOOL;       // группа 3 (DO8)
    AO_HeaterPower      : REAL;       // 0..100 %, аналоговая команда (для группы 1 / индикации)

    // Отфильтрованные температуры:
    PV_TempProduct      : REAL;       // °C
    PV_TempJacket       : REAL;       // °C
END_VAR

VAR
    // Фильтр
    alpha               : REAL;       // 0..1

    // Внутреннее состояние гистерезиса
    heat_state          : BOOL;       // текущий «вкл/выкл»
    last_on_sec         : UDINT;
    last_off_sec        : UDINT;
    equilize_until      : UDINT;

    // Внутреннее ПИД
    pid_i               : REAL;
    pv_prev             : REAL;
    last_sec_ud         : UDINT;

    // Общие
    EffPowerPct         : REAL;       // 0..100 % — итоговая мощность для ШИМ
    period_s            : UDINT;
    periodR             : REAL;
    tposR               : REAL;

    // Локальные рабочие
    dtR                 : REAL;
    err                 : REAL;
    pTerm               : REAL;
    iTerm               : REAL;
    dTerm               : REAL;

    g2_start            : REAL;
    g3_start            : REAL;

    jacket_guard        : BOOL;
END_VAR

// ===== ФИЛЬТР АЛЬФА =====
IF PAR_FilterAlpha_x1000 >= 1000 THEN
    alpha := 1.0;
ELSE
    alpha := UDINT_TO_REAL(PAR_FilterAlpha_x1000) / 1000.0;
    IF alpha < 0.0 THEN alpha := 0.0; END_IF;
END_IF;

// ===== ИНИЦИАЛИЗАЦИЯ ПРИ ИЗМЕНЕНИИ ВРЕМЕНИ =====
IF last_sec_ud = 0 THEN
    last_sec_ud := Seconds_UD;
    PV_TempProduct := PV_TempProduct_Raw;
    PV_TempJacket  := PV_TempJacket_Raw;
    last_off_sec   := Seconds_UD;
END_IF;

// ===== ФИЛЬТРАЦИЯ ТЕМПЕРАТУР =====
IF alpha <= 0.0 THEN
    PV_TempProduct := PV_TempProduct_Raw;
    PV_TempJacket  := PV_TempJacket_Raw;
ELSE
    PV_TempProduct := PV_TempProduct + alpha * (PV_TempProduct_Raw - PV_TempProduct);
    PV_TempJacket  := PV_TempJacket  + alpha * (PV_TempJacket_Raw  - PV_TempJacket);
END_IF;

// ===== ТАЙМЕРЫ / DT =====
IF Seconds_UD >= last_sec_ud THEN
    dtR := UDINT_TO_REAL(Seconds_UD - last_sec_ud);
ELSE
    dtR := 1.0; // на всякий случай
END_IF;
IF dtR <= 0.0 THEN dtR := 1.0; END_IF;
last_sec_ud := Seconds_UD;

// ===== НОРМАЛИЗАЦИЯ ПАРАМЕТРОВ =====
period_s := PAR_PWM_Period_s; IF period_s = 0 THEN period_s := 1; END_IF;
periodR  := UDINT_TO_REAL(period_s);

g2_start := PAR_G2_StartPct; IF g2_start < 0.0 THEN g2_start := 0.0; END_IF; IF g2_start > 100.0 THEN g2_start := 100.0; END_IF;
g3_start := PAR_G3_StartPct; IF g3_start < 0.0 THEN g3_start := 0.0; END_IF; IF g3_start > 100.0 THEN g3_start := 100.0; END_IF;

// ===== ОГРАНИЧЕНИЕ ПО ΔT РУБАШКА–ПРОДУКТ =====
jacket_guard := (PV_TempJacket > (PV_TempProduct + SmoothDiffGuard));

// ===== ОСНОВНОЙ ВЫБОР ТРАКТА (PID / HYST) =====
IF (NOT EN_Heat) THEN
    // Нагрев запрещён окном стадии — всё в ноль
    EffPowerPct := 0.0;
    heat_state  := FALSE;

    // анти-виндап: подпритормаживаем интегратор
    IF PAR_PID_Ti > 0.0 THEN
        pid_i := pid_i * 0.98;
    ELSE
        pid_i := 0.0;
    END_IF;

ELSE
    IF PAR_UsePID THEN
        // ===== ПИД-тракт =====
        err  := SP_TempTarget - PV_TempProduct;

        // P
        pTerm := PAR_PID_Kp * err;

        // I (с анти-виндапом)
        IF PAR_PID_Ti > 0.0 THEN
            pid_i := pid_i + (err / PAR_PID_Ti) * dtR;
            // ограничим вклад интегратора
            IF pid_i > 100.0 THEN pid_i := 100.0; END_IF;
            IF pid_i < -100.0 THEN pid_i := -100.0; END_IF;
            iTerm := pid_i;
        ELSE
            iTerm := 0.0;
        END_IF;

        // D по PV (чтобы не дёргалось на скачке SP)
        IF PAR_PID_Td > 0.0 THEN
            dTerm := - PAR_PID_Td * (PV_TempProduct - pv_prev) / dtR;
        ELSE
            dTerm := 0.0;
        END_IF;
        pv_prev := PV_TempProduct;

        // Сумма и кламп 0..100 %
        EffPowerPct := pTerm + iTerm + dTerm;
        IF EffPowerPct < 0.0 THEN EffPowerPct := 0.0; END_IF;
        IF EffPowerPct > 100.0 THEN EffPowerPct := 100.0; END_IF;

        // Ограничение по рубашке
        IF jacket_guard THEN
            IF PAR_MaxDutyPct_JacketGuard < EffPowerPct THEN
                EffPowerPct := PAR_MaxDutyPct_JacketGuard;
            END_IF;
        END_IF;

    ELSE
        // ===== Гистерезис-тракт =====
        // ВКЛ:  PV ≤ SP − OnBelow   и выдержан MinOff   и не превышена ΔT рубашки
        // ВЫКЛ: PV ≥ SP − OffEarly  и выдержан MinOn
        // Пауза «уравновешивания» после выключения: HYST_Equilize_s

        // Блокировка включения на период уравновешивания
        IF Seconds_UD < equilize_until THEN
            heat_state := FALSE;
        ELSE
            IF NOT heat_state THEN
                // было выкл — проверяем условия на включение
                IF (PV_TempProduct <= (SP_TempTarget - HYST_OnBelow)) AND
                   ((Seconds_UD - last_off_sec) >= HYST_MinOff_s) AND
                   (NOT jacket_guard) THEN
                    heat_state := TRUE;
                    last_on_sec := Seconds_UD;
                END_IF;
            ELSE
                // было вкл — проверяем условия на выключение
                IF (PV_TempProduct >= (SP_TempTarget - HYST_OffEarly)) AND
                   ((Seconds_UD - last_on_sec) >= HYST_MinOn_s) THEN
                    heat_state := FALSE;
                    last_off_sec := Seconds_UD;
                    equilize_until := Seconds_UD + HYST_Equilize_s; // пауза уравновешивания
                END_IF;
            END_IF;
        END_IF;

        // Итоговая мощность: двоичная (0/100), с ограничением по рубашке
        IF heat_state THEN
            IF jacket_guard THEN
                EffPowerPct := PAR_MaxDutyPct_JacketGuard; // мягче, если ΔT велика
            ELSE
                EffPowerPct := 100.0;
            END_IF;
        ELSE
            EffPowerPct := 0.0;
        END_IF;

        // при гистерезисе интегратор не накапливаем
        pid_i := 0.0;
        pv_prev := PV_TempProduct;
    END_IF;
END_IF;

// ===== ШИМ И КАСКАД ГРУПП =====
IF EffPowerPct < 0.0 THEN EffPowerPct := 0.0; END_IF;
IF EffPowerPct > 100.0 THEN EffPowerPct := 100.0; END_IF;

// duty и позиция внутри периода
tposR := UDINT_TO_REAL(Seconds_UD MOD period_s);
DO_Heater1_Cmd := (EffPowerPct > 0.0) AND (tposR < (periodR * (EffPowerPct / 100.0)));

// Аналог — просто % (можно ограничить отдельно при необходимости)
AO_HeaterPower := EffPowerPct;

// Группы 2/3 — по порогам и тем же импульсам (одинаковый duty)
IF (EffPowerPct >= g2_start) AND PAR_HeaterGroup2Enabled THEN
    DO_Heater2_Cmd := DO_Heater1_Cmd;
ELSE
    DO_Heater2_Cmd := FALSE;
END_IF;

IF (EffPowerPct >= g3_start) AND PAR_HeaterGroup3Enabled THEN
    DO_Heater3_Cmd := DO_Heater1_Cmd;
ELSE
    DO_Heater3_Cmd := FALSE;
END_IF;

END_FUNCTION_BLOCK
