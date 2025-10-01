FUNCTION_BLOCK FB_ActuatorManager
VAR_INPUT
    // Команды от PasteurManager:
    Pasteur_CircPump_ON     : BOOL;
    Pasteur_Mixer_ON        : BOOL;
    Pasteur_CoolingValve_ON : BOOL;
    Pasteur_HeatPowerReq    : REAL;

    // Команды от CIPManager:
    CIP_Valve_Cold_ON  : BOOL;  // холодная вода (CIP)
    CIP_Valve_Hot_ON   : BOOL;  // горячая вода (CIP)
    CIP_Valve_Alk_ON   : BOOL;
    CIP_Valve_Acid_ON  : BOOL;
    CIP_Pump_ON        : BOOL;
    CIP_DrainValve_ON  : BOOL;
    CIP_Mixer_ON       : BOOL;  // <<< новый вход: мешалка по уставкам этапов CIP

    // Команды от DosingManager:
    Dosing_FillPump_ON : BOOL;

    // Команды от TemperatureManager:
    Temp_DO_Heater1_Cmd : BOOL;
    Temp_DO_Heater2_Cmd : BOOL;
    Temp_DO_Heater3_Cmd : BOOL;
    Temp_AO_HeaterPower : REAL;

    // Mixer/VFD (на будущее):
    VFD_MixerRunReq    : BOOL;
    VFD_MixerRevReq    : BOOL;

    // ===== РУЧНЫЕ КОМАНДЫ (1:1 c физическими DO) =====
    Man1_ValveCold        : BOOL;
    Man2_CircPump         : BOOL;
    Man3_MixerFwd         : BOOL;
    Man4_MixerRev         : BOOL;
    Man5_PumpDisp         : BOOL;
    Man6_Heater1          : BOOL;
    Man7_Heater2          : BOOL;
    Man8_Heater3          : BOOL;
    Man9_ValveCIP_Cold    : BOOL;
    Man10_ValveCIP_Hot    : BOOL;
    Man11_ValveAlk        : BOOL;
    Man12_ValveAcid       : BOOL;
    Man13_PumpCIP         : BOOL;
    Man14_ValveDrain      : BOOL;

    // Флаги режимов:
    Mode_Pasteur_ACTIVE   : BOOL;
    Mode_CIP_ACTIVE       : BOOL;
    Mode_Dosing_ACTIVE    : BOOL;
    Mode_Manual_ACTIVE    : BOOL;
    Mode_Recipe_ACTIVE    : BOOL;

    // Блокировки:
    BLOCK_AllOff          : BOOL;
    BLOCK_HeaterOff       : BOOL;

    // Параметры:
    PAR_UseVFD            : BOOL;
END_VAR

VAR_OUTPUT
    // — Карта выходов ПЛК — (имена строго как в FB_Main)
    DO1_ValveCold       : BOOL; // клапан охлаждения (хол. вода)
    DO2_CircPump        : BOOL; // циркуляционный насос
    DO3_MixerFwd        : BOOL;
    DO4_MixerRev        : BOOL;
    DO5_PumpDisp        : BOOL;
    DO6_Heater1         : BOOL;
    DO7_Heater2         : BOOL;
    DO8_Heater3         : BOOL;
    DO9_ValveCIP_Cold   : BOOL;
    DO10_ValveCIP_Hot   : BOOL;
    DO11_ValveAlk       : BOOL;
    DO12_ValveAcid      : BOOL;
    DO13_PumpCIP        : BOOL;
    DO14_ValveDrain     : BOOL;

    // — Аналог —
    AO_1  : REAL;       // мощность нагрева 0..10 В
    AO_2  : REAL;       // резерв / «старт» (если не VFD)
END_VAR

// ========== Безопасные значения по умолчанию ==========
DO1_ValveCold:=FALSE; DO2_CircPump:=FALSE; DO3_MixerFwd:=FALSE; DO4_MixerRev:=FALSE; DO5_PumpDisp:=FALSE;
DO6_Heater1:=FALSE; DO7_Heater2:=FALSE; DO8_Heater3:=FALSE; DO9_ValveCIP_Cold:=FALSE; DO10_ValveCIP_Hot:=FALSE;
DO11_ValveAlk:=FALSE; DO12_ValveAcid:=FALSE; DO13_PumpCIP:=FALSE; DO14_ValveDrain:=FALSE;
AO_1:=0.0; AO_2:=0.0;

// ========== ЛОГИКА ==========
IF NOT BLOCK_AllOff THEN

    // DO1 — клапан охлаждения (пастеризатор)
    IF Mode_Manual_ACTIVE THEN
        DO1_ValveCold := Man1_ValveCold;
    ELSIF Mode_Pasteur_ACTIVE OR Mode_Recipe_ACTIVE THEN
        DO1_ValveCold := Pasteur_CoolingValve_ON;
    ELSE
        DO1_ValveCold := FALSE;
    END_IF;

    // DO2 — циркуляционный насос (пастеризатор)
    IF Mode_Manual_ACTIVE THEN
        DO2_CircPump := Man2_CircPump;
    ELSIF Mode_CIP_ACTIVE THEN
        DO2_CircPump := FALSE; // при необходимости можно разрешить в CIP
    ELSIF Mode_Pasteur_ACTIVE OR Mode_Recipe_ACTIVE THEN
        DO2_CircPump := Pasteur_CircPump_ON;
    ELSE
        DO2_CircPump := FALSE;
    END_IF;

    // DO3/DO4 — мешалка
    IF Mode_Manual_ACTIVE THEN
        DO3_MixerFwd := Man3_MixerFwd;
        DO4_MixerRev := Man4_MixerRev;
    ELSE
        IF Mode_CIP_ACTIVE THEN
            // В режиме CIP — только вперёд, по сигналу от FB_CIPManager_v2
            DO3_MixerFwd := CIP_Mixer_ON;
            DO4_MixerRev := FALSE;
        ELSIF Mode_Pasteur_ACTIVE OR Mode_Recipe_ACTIVE THEN
            DO3_MixerFwd := Pasteur_Mixer_ON;
            DO4_MixerRev := FALSE;
        ELSE
            DO3_MixerFwd := FALSE;
            DO4_MixerRev := FALSE;
        END_IF;
    END_IF;

    // защита от одновременного FWD/REV
    IF DO3_MixerFwd AND DO4_MixerRev THEN
        DO4_MixerRev := FALSE;
    END_IF;

    // DO5 — насос розлива/дозирования
    IF Mode_Manual_ACTIVE THEN
        DO5_PumpDisp := Man5_PumpDisp;
    ELSIF Mode_Dosing_ACTIVE THEN
        DO5_PumpDisp := Dosing_FillPump_ON;
    ELSE
        DO5_PumpDisp := FALSE;
    END_IF;

    // DO6..DO8 — нагрев и AO_1
    IF BLOCK_HeaterOff THEN
        DO6_Heater1 := FALSE; DO7_Heater2 := FALSE; DO8_Heater3 := FALSE;
        AO_1 := 0.0;
    ELSIF Mode_Manual_ACTIVE THEN
        DO6_Heater1 := Man6_Heater1;
        DO7_Heater2 := Man7_Heater2;
        DO8_Heater3 := Man8_Heater3;
        AO_1 := 0.0;
    ELSE
        DO6_Heater1 := Temp_DO_Heater1_Cmd;
        DO7_Heater2 := Temp_DO_Heater2_Cmd;
        DO8_Heater3 := Temp_DO_Heater3_Cmd;
        AO_1 := Temp_AO_HeaterPower;
    END_IF;

    // DO9..DO14 — CIP-исполнительные механизмы
    IF Mode_Manual_ACTIVE THEN
        DO9_ValveCIP_Cold := Man9_ValveCIP_Cold;
    ELSIF Mode_CIP_ACTIVE THEN
        DO9_ValveCIP_Cold := CIP_Valve_Cold_ON;
    ELSE
        DO9_ValveCIP_Cold := FALSE;
    END_IF;

    IF Mode_Manual_ACTIVE THEN
        DO10_ValveCIP_Hot := Man10_ValveCIP_Hot;
    ELSIF Mode_CIP_ACTIVE THEN
        DO10_ValveCIP_Hot := CIP_Valve_Hot_ON;
    ELSE
        DO10_ValveCIP_Hot := FALSE;
    END_IF;

    IF Mode_Manual_ACTIVE THEN
        DO11_ValveAlk := Man11_ValveAlk;
    ELSIF Mode_CIP_ACTIVE THEN
        DO11_ValveAlk := CIP_Valve_Alk_ON;
    ELSE
        DO11_ValveAlk := FALSE;
    END_IF;

    IF Mode_Manual_ACTIVE THEN
        DO12_ValveAcid := Man12_ValveAcid;
    ELSIF Mode_CIP_ACTIVE THEN
        DO12_ValveAcid := CIP_Valve_Acid_ON;
    ELSE
        DO12_ValveAcid := FALSE;
    END_IF;

    IF Mode_Manual_ACTIVE THEN
        DO13_PumpCIP := Man13_PumpCIP;
    ELSIF Mode_CIP_ACTIVE THEN
        DO13_PumpCIP := CIP_Pump_ON;
    ELSE
        DO13_PumpCIP := FALSE;
    END_IF;

    IF Mode_Manual_ACTIVE THEN
        DO14_ValveDrain := Man14_ValveDrain;
    ELSIF Mode_CIP_ACTIVE THEN
        DO14_ValveDrain := CIP_DrainValve_ON;
    ELSE
        DO14_ValveDrain := FALSE;
    END_IF;

    // AO_2 — если VFD не используется (имитация «старта»)
    IF NOT PAR_UseVFD THEN
        IF DO3_MixerFwd OR DO4_MixerRev THEN
            AO_2 := 100.0; // %
        ELSE
            AO_2 := 0.0;
        END_IF;
    ELSE
        AO_2 := 0.0;
    END_IF;

END_IF;

END_FUNCTION_BLOCK
