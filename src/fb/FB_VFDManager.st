FUNCTION_BLOCK FB_VFDManager
VAR_INPUT
    PAR_UseVFD      : BOOL;   // 1 = управление по Modbus, 0 = локальное/аналоговое
    MB_SetMixerFreq : UDINT;  // 0..1000 = 0..100.0% от 50.00 Гц
    MixerRunCmd     : BOOL;   // Пуск вперед
    MixerRevCmd     : BOOL;   // Пуск реверс
    MixerStopCmd    : BOOL;   // Стоп
END_VAR
VAR_OUTPUT
    VFD_SetFreqWord : UDINT;  // 0..50000 = 0.00..50.00 Гц (шаг 0.01 Гц)
    VFD_CmdWord     : UDINT;  // Командное слово ПЧ (Modbus)
    VFD_Status      : UDINT;  // Слово статуса ПЧ (обновляется извне)
    VFD_Fault       : BOOL;   // Авария ПЧ (по статусу)
END_VAR
VAR
    freqSetHz : UDINT;        // целевая частота в сотых Гц
    K_50      : UDINT := 50;  // множитель для перевода %*10 → 0.01 Гц (1000 * 50 = 50000)
END_VAR

// значения по умолчанию (если PAR_UseVFD=0, они и останутся)
VFD_SetFreqWord := 0;
VFD_CmdWord     := 0;
VFD_Fault       := FALSE;

IF PAR_UseVFD THEN
    // 0..1000 (%*10) → 0..50000 (0.01 Гц)
    IF MB_SetMixerFreq > 1000 THEN
        freqSetHz := 50000;            // насыщаем до 50.00 Гц
    ELSE
        freqSetHz := MB_SetMixerFreq * K_50;
    END_IF;
    VFD_SetFreqWord := freqSetHz;      // (обычно в Holding-рег 0x9000)

    // Командное слово
    IF MixerRunCmd AND NOT MixerRevCmd THEN
        VFD_CmdWord := 1;              // Пуск вперед
    ELSIF MixerRevCmd THEN
        VFD_CmdWord := 2;              // Пуск реверс
    ELSIF MixerStopCmd THEN
        VFD_CmdWord := 6;              // Стоп (пример кода)
    ELSE
        VFD_CmdWord := 0;              // Нет команды
    END_IF;

    // Диагностика: пример — бит 3 в слове статуса = авария
    // Удобнее так (побитовый доступ для UDINT):
    IF VFD_Status.3 THEN
        VFD_Fault := TRUE;
    ELSE
        VFD_Fault := FALSE;
    END_IF;
END_IF;

END_FUNCTION_BLOCK
