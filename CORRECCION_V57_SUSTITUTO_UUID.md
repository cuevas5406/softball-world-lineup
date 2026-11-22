# V5.7 — Validación del sustituto de corredor

La RPC `swl_v56_special_play`, rama `RUNNER_REPLACE`, ahora comprueba que `player_id` tenga formato UUID antes de convertirlo. Rechaza valores vacíos, `LAST_OUT` y texto arbitrario con un error explícito. Conserva las comprobaciones de origen, duplicación, autorización y sustitución transaccional existentes.

**Alcance:** cambio de SQL preparado, **no ejecutado** en Supabase LAB ni producción. Flutter y APK no probados.
