# V5.6 — Validación de defensa frente a LAB

La RPC `swl_v56_save_lineup` requiere `p_pitcher_id` no nulo, `p_defensive_positions` como objeto, de 9 a 10 asignaciones y que el pitcher tenga la posición `P`.

Se corrigió `lib/swl_lineup_draft.dart` para impedir guardar borradores con menos de 9 posiciones o sin pitcher. Se agregó una prueba de regresión en `test/swl_lineup_draft_test.dart`.

**Pendiente:** actualizar los tests anteriores que trataban defensas parciales como alineaciones completas. No se ejecutaron pruebas Flutter ni se compiló APK (Flutter no está instalado en este entorno). No se ejecutó SQL de escritura ni se modificó Supabase LAB.
