# Matriz de validación V5.7 — doble play y fly de sacrificio

Estado: casos definidos a partir de `lib/swl_advanced_scoreboard.dart`, `lib/swl_special_play.dart` y `propuestas_lab/09_jugadas_especiales.sql`. **No ejecutados** contra LAB ni APK.

| Caso | Preparación | Resultado exigido |
|---|---|---|
| DP-01 | 0 outs, corredor en primera | Dos outs; corredor de primera eliminado; bateador fuera; 0 hits; avance del turno; evento DOUBLE_PLAY |
| DP-02 | 1 out, corredor en primera | Tercer out; cambio automático de media entrada; bases vacías; 0 hits; evento DOUBLE_PLAY |
| DP-03 | 2 outs, corredor en primera | Doble play no ofrecido; no se debe generar un cuarto out |
| DP-04 | 0 outs, bases vacías | Doble play no ofrecido |
| SF-01 | 0 outs, corredor en tercera | 1 out; 1 carrera; 0 hits; SF=1, AB=0; evento SACRIFICE_FLY |
| SF-02 | 1 out, corredores en primera y tercera | 2 outs; carrera de tercera; primera puede permanecer; sin hit |
| SF-03 | 2 outs, corredor en tercera | Fly de sacrificio no ofrecido; no se registra carrera por esa acción |
| SF-04 | 0 outs, sin corredor en tercera | Fly de sacrificio no ofrecido |
| SYNC-01 | Dos teléfonos, anotación autorizada | Marcador, outs, bases, historial y versión coinciden; el mánager no autorizado no puede anotar |
| REG-01 | Partido anterior FINAL/OFFICIAL | Ninguna función de prueba altera el partido existente |

## Bloqueos previos a pruebas reales
- En LAB no están instaladas `swl_v56_special_play`, `swl_v57_batted_ball`, `swl_v56_lock_batting_turn`, `swl_v56_accumulate_pitching`, `swl_v56_close_after_play`.
- Falta `swl_base_players` y dependencias de identidad de corredores.
- Las propuestas `06`, `08`, `09`, `11`, `13` y `15` redefinen funciones entre sí; no deben ejecutarse en bloque.
- La regla de carreras con tercer out en `13_v57_batazos_y_defensa.sql` necesita una representación fiable de la naturaleza y orden de los outs.

## Criterio de liberación
No generar APK de pruebas como corrección de estas jugadas hasta validar la migración diferencial y ejecutar los casos DP/SF con resultados registrados. No modificar producción.
