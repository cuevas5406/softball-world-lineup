# V5.7 — autenticación y validación de jugador

Se adelantó la comprobación de `auth.uid()` al inicio de la RPC `swl_v56_special_play`, antes de interpretar parámetros externos. Se añadió validación de `player_id` para `RUNNER_REPLACE` y `GHOST_RUNNER`: solo UUID textual canónico, o `LAST_OUT` exclusivamente para corredor fantasma. Esto evita conversiones UUID opacas y solicitudes sin sesión.

**Pendiente:** ejecutar y probar la migración en LAB, sin tocar producción. No se ejecutaron pruebas Flutter ni SQL en esta revisión.
