# Diagnóstico RPC LAB — Softball World Lineup V5.7

## Alcance
Inspección de solo lectura del proyecto LAB `wgeziptdoabyicufnrfk` y de las propuestas SQL presentes en `propuestas_lab/`. No se ha desplegado ninguna migración.

## Confirmaciones
- En LAB existen `swl_v56_apply_hit`, `swl_v56_record_plate_action`, `swl_v56_save_lineup` y varias RPC V5.3.
- No existen `swl_v56_special_play`, `swl_v57_batted_ball`, `swl_v56_lock_batting_turn`, `swl_v56_accumulate_pitching`, `swl_v56_add_inning_runs`, `swl_v56_base_occupancy`, `swl_v56_close_after_play`.
- `swl_live_games` tiene restricciones de outs entre 0 y 2, y columnas de carreras/hits/errores; `swl_game_events` admite event_data JSONB.
- Los archivos `06`, `07`, `08`, `09`, `11` y `13` contienen dependencias y redefiniciones entre sí. Ejecutarlos directamente no constituye una migración segura.

## Bloqueadores detectados en código
1. `13_v57_batazos_y_defensa.sql`, líneas 82–92: tratamiento del tercer out basado en `count_runs_on_third_out`, `last_out_source` y orden de recorrido, sin representación inequívoca de tiempos de llegada ni clasificación completa de out forzado. Riesgo de contabilizar carreras incorrectamente.
2. `09_jugadas_especiales.sql` requiere `swl_base_players`, `swl_v56_lock_batting_turn`, `swl_v56_validate_base_players`, `swl_v56_close_after_play` y otras dependencias.
3. `06_anotacion_y_pitcheo.sql` crea RPC V5.6 que ya existen en LAB con firmas compatibles; `08` y `09` vuelven a reemplazarlas. Requiere migración diferencial y revisión de seguridad/permisos.
4. El código de `13` llama a `swl_v56_accumulate_pitching` y `swl_v56_close_after_play`, ausentes de LAB.

## Recomendación técnica
No desplegar los scripts originales como están. Preparar migración diferencial idempotente, validar la semántica de outs/carreras, revisar seguridad de las funciones SECURITY DEFINER y comprobar permisos de anotación, Realtime e historial en un partido nuevo de prueba. Mantener producción fuera del alcance.
