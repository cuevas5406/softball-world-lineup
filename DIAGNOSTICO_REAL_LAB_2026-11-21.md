# Diagnóstico REAL Supabase LAB — 21 noviembre 2026

Proyecto consultado: `wgeziptdoabyicufnrfk` (LAB). Solo lectura.

## Resultados observados

- `swl_v56_special_play(uuid,bigint,text,uuid,jsonb)`: **NO instalada**.
- `swl_v57_batted_ball(uuid,bigint,text,uuid,jsonb)`: **NO instalada** (firma exacta consultada).
- Columnas `swl_base_players`, `swl_ghost_player`, `swl_regulation_innings`, `swl_allow_roster_ghost`: **4 de 4 presentes**.
- `swl_v56_lock_batting_turn(uuid,bigint)`: **instalada**.
- `swl_v56_validate_base_players(boolean[],uuid[])`: **instalada**.
- `swl_v56_add_inning_runs(jsonb,integer,integer)`: **instalada**.
- `swl_v56_accumulate_pitching(swl_live_games,uuid,text)`: **instalada**.
- `swl_v56_close_after_play(swl_live_games)`: **instalada**.
- `swl_v53_substitute_batter(uuid,uuid,integer,uuid,uuid,bigint,bigint)`: **instalada**.

Las seis dependencias enumeradas de `swl_v56_special_play` están disponibles. Esto **no** prueba que la migración compile ni que las jugadas funcionen: falta validar los tipos, permisos y ejecutar pruebas de integración.

## Próximos pasos técnicos

1. Comprobar estructura exacta de `swl_game_events`, `swl_game_lineups`, `rosters`, `swl_live_games` y permisos de las funciones auxiliares.
2. Revisar en especial la consulta del último out y los tipos de `event_data`, `event_type`, `version`, `batting_team_id`.
3. Aplicar migraciones solo en LAB una vez comprobadas las dependencias completas; después ejecutar pruebas de anotación con usuario autenticado.
4. Verificar la actualización atómica del historial y Realtime entre dos teléfonos.

**No se ejecutaron cambios de base de datos ni se compiló una APK. Producción no fue consultada ni modificada.**
