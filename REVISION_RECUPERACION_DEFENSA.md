# Recuperación de la defensa al reabrir una alineación

Hallazgo: `_editLineup` reconstruía `selected` exclusivamente desde `lineup` y `pitcher_id`, descartando a otros jugadores que aparecieran en `defensive_positions` sin turno al bate.

Corrección: incluir las claves de `defensive_positions` que sigan en el roster activo al reconstruir el borrador. Se conserva el orden original de los bateadores, seguido de los defensores adicionales. No se cambia Supabase ni se ejecuta SQL.

Verificación: comprobación estática de la rama de restauración y de la integridad del ZIP. `flutter test` y APK siguen pendientes.
