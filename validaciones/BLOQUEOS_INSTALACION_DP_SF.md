# Revisión real de instalación — doble play y fly de sacrificio (LAB)

Fecha: 2026-11-20. Estado: **NO INSTALADO**.

## Confirmaciones

- El cliente Flutter usa `swl_v56_special_play` para `DOUBLE_PLAY` y `SACRIFICE_FLY` (`lib/swl_live_lobby.dart`, `lib/swl_advanced_scoreboard.dart`).
- La función propuesta en `propuestas_lab/09_jugadas_especiales.sql` exige `swl_v56_lock_batting_turn`, `swl_v56_accumulate_pitching`, `swl_v56_close_after_play`, columnas de identidad y auxiliares aún no disponibles en LAB.
- El archivo 09 también **reemplaza** `swl_v56_record_plate_action`, `swl_v56_apply_hit` y `swl_v56_substitute_batter`: una instalación indiscriminada altera operaciones previamente verificadas.
- `propuestas_lab/13_v57_batazos_y_defensa.sql` contiene una rama de tercer out que reinicia `runs` y recupera carreras solo en casos específicos; no se ha validado el orden temporal de las anotaciones respecto del tercer out.
- `propuestas_lab/08_cierre_transaccional.sql` y `15_v57_cierre_reglamentario.sql` contienen versiones diferentes de `swl_v56_close_after_play`; es necesario decidir la versión final antes de desplegar.

## Bloqueos para instalación segura

1. Verificar dependencias de los scripts 01, 05, 06, 07, 08, 09, 11 y 15 y el orden de reemplazos.
2. Diseñar la transición de identidad de corredores en partidos ya iniciados: bases ocupadas pueden carecer de `player_id`.
3. Corregir regla del tercer out en batazos, incluyendo outs forzados y anotaciones previas al tercer out no forzado.
4. Probar en transacción con rollback, sin modificar partidos reales, antes de publicar la migración.
5. Validar permisos de los RPC `SECURITY DEFINER` y el control de versión para dos teléfonos.

## Próxima acción

Preparar un conjunto de migraciones revisadas y pruebas reproducibles; **no ejecutar los SQL originales completos**. La autorización del usuario aplica solo a LAB. Producción excluida.
