# V5.7 — LAB y validación de batazos (21 noviembre 2026)

Consulta de solo lectura ejecutada en Supabase LAB `wgeziptdoabyicufnrfk`:
- `swl_v56_special_play` y `swl_v57_batted_ball`: **ausentes**.
- Seis funciones auxiliares de jugadas especiales: **presentes**.
- `swl_v56_base_occupancy`, `swl_can_manage_roster`, tabla de cambios de pitcher y las tres columnas de defensa verificadas: **presentes**.
- `swl_game_events.event_type` es `text`, `event_data` es `jsonb`, `version` es `bigint`.
- `swl_live_games.swl_base_players` es `uuid[]`; entradas por inning son `jsonb`.

Corrección aplicada a `propuestas_lab/13_v57_batazos_y_defensa.sql`:
- Autenticación antes de leer y convertir campos JSON.
- Verificación de que `p_data` sea objeto JSON.
- Comprobación de tipos y formato de las bases antes de `::integer`, evitando errores de conversión por cadenas, decimales o exponentes.
- Conversión de `drives` y `batter_base` dentro del bloque `begin`, después de validar.

**No se han aplicado migraciones ni probado jugadas en PostgreSQL**. Producción `epqyabaegmyjtwqezvbc` no se tocó. Flutter SDK/APK no ejecutados.
