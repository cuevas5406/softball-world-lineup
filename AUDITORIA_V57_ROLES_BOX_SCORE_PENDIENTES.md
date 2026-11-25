# Auditoría pendiente V5.7 — estadísticas y Box Score

Base revisada: rama `pruebas-de-V5.7`, commit inicial de roles `9fb833c`. **Informe de revisión estática; no es evidencia de pruebas Android ni de ejecución SQL.**

## Hallazgos que bloquean la activación de la propuesta 28 en LAB

1. `swl_private.game_batting` devuelve AB, H, HR, BB, K y SF, pero no devuelve dobles, triples, carreras anotadas (R) ni impulsadas (RBI). El PDF actual tampoco ofrece R/RBI ni 2B/3B. No presentar este desglose como un box score completo.
2. La estadística de bateo se infiere de `swl_game_events` usando `event_type`, `event_data.batter_id`, `event_data.batter_base` y `plate_appearance_completed`. Antes de instalar la migración, cotejar esos campos con eventos reales de pruebas desechables y verificar HIT sencillo/doble/triple/HR, BB, K, error, DP, SF, outs de corredores y UNDO_OUT.
3. La consulta de pitcheo de `swl_v57_spectator_game` agrupa por pitcher, pero no devuelve el equipo; el PDF muestra una sola tabla sin atribución explícita de club. Validar cambios de pitcher y apariciones en equipos diferentes.
4. `swl_v57_my_player` depende de una invitación emitida por operador; la migración no crea un flujo administrativo de emisión. Definir quién verifica la identidad, genera el token y registra la auditoría, sin habilitar autoasignación por código SWL.
5. El cliente sube fotos con rutas nuevas, pero no borra archivos antiguos ni archivos huérfanos si falla el RPC. La propuesta Storage solo define INSERT y SELECT. Diseñar borrado seguro de objetos propios no referenciados antes de activarlo.
6. `swl_v57_spectator_game` permite consultar alineaciones de juegos en progreso a cualquier usuario autenticado. Revisar momento de publicación, visibilidad deseada y campos antes de exponerlo.
7. Los favoritos de fanático son locales al dispositivo; no se sincronizan entre teléfono y tableta.
8. Las pruebas `swl_box_score_export_test.dart` verifican firmas de archivo y algunas entradas, pero no los cálculos de estadísticas contra eventos reales ni la apertura en WhatsApp.

## Próximas acciones sin tocar Supabase

- Corregir y ampliar el modelo de estadísticas con pruebas basadas en la semántica real de eventos.
- Completar columnas del PDF y atribución de equipos.
- Diseñar limpieza de fotos y flujo administrativo de invitaciones.
- Ejecutar Flutter analyze/test y pruebas de regresión tras cambios.
- Consolidar commits; **no generar APK por cada corrección**.

**Estado:** SQL 28 no autorizado ni ejecutado. No modificar producción ni partidos de referencia.
