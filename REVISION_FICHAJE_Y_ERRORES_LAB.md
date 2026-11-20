# Verificación de fichaje y errores de alineación — LAB (solo lectura)

## Contratos consultados en LAB

- `swl_sign_player(p_team_id uuid, p_player_id uuid, p_is_refuerzo boolean DEFAULT false) RETURNS uuid`. Comprueba `swl_can_manage_roster`, crea/reactiva fichaje y devuelve ID del roster. Flutter ya invoca esta función tras registrar el pelotero y dispone de un intento de recuperación si falla.
- `swl_v53_save_lineup_checked(p_game_id uuid, p_team_id uuid, p_player_ids uuid[], p_expected_revision bigint) RETURNS jsonb`. Rechaza revisión desactualizada con `STALE_LINEUP_REVISION` y bloquea cambios después de una acción de bateo.
- `swl_v56_save_lineup` exige pitcher P, coherencia con `pitcher_bats`, DH compatible y defensa válida.

## Cambio aplicado en Flutter

En `lib/swl_live_lobby.dart` se amplió el mensaje de errores para `PITCHER_INVALID`, `DESIGNATED_HITTER_INVALID`, `DEFENSIVE_POSITIONS_*` y `STALE_LINEUP_REVISION`. No se alteró la lógica de guardado ni la base de datos.

## Riesgos pendientes

- El alta y fichaje siguen siendo dos RPC independientes: un fallo de red entre ambas puede dejar un jugador creado sin fichaje. El flujo actual permite recuperar ese caso, pero no es transacción única.
- Se debe revisar el uso de `swl_v53_save_lineup_checked` como alternativa al guardado V5.6, porque la función V5.6 de inicio exige ambas alineaciones con pitcher y posiciones. No se modificó esa ruta sin pruebas.
- No se ejecutaron pruebas Flutter ni compilación APK en esta revisión.
- No se ejecutaron escrituras ni propuestas SQL en Supabase.
