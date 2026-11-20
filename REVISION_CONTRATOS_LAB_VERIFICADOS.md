# Contratos de Supabase LAB verificados — SWL V5.6

Fecha de revisión: 19 de noviembre de 2026. Consulta exclusivamente SELECT a pg_proc; **ningún cambio en LAB**.

- `swl_register_player(text,text,text,text,text)` devuelve `TABLE(player_id uuid, universal_id text)`; `SECURITY DEFINER`, EXECUTE autenticado sí, anónimo no.
- `swl_can_manage_roster(uuid)` devuelve boolean; valida administradores o mánagers activos.
- `swl_v56_save_lineup(uuid,uuid,uuid[],integer,uuid,boolean,uuid,jsonb)` devuelve void. Requiere P asignada al pitcher, coherencia con pitcher_bats, 9–13 bateadores, 9–10 posiciones defensivas únicas y jugadores del roster. Errores relevantes: `INVALID_PITCHER_OR_POSITIONS`, `PITCHER_INVALID`, `DESIGNATED_HITTER_INVALID`.
- `swl_v56_start_game(uuid,bigint)` devuelve void; exige ambas alineaciones y ambos mánagers.

## Corrección en propuesta 12
Se añadió `EP` a posiciones principales admitidas, coherente con el valor predeterminado real de `swl_register_player`. `EP` no se añadió a las posiciones defensivas del encuentro, donde no está permitido. Se actualizaron comentarios de la propuesta. **SQL preparado, no ejecutado**.

## Hallazgo Flutter
`main.dart` registra el pelotero mediante `swl_register_player` o `swl_v56_register_player_positions`, extrae `player_id` y luego llama `swl_sign_player`. Ya hay mensaje de recuperación cuando falla el fichaje. No es correcto afirmar que Flutter omite el fichaje.

## Pendiente antes de aplicar
Verificar la firma de `swl_sign_player`, el comportamiento de las funciones de alineación en la UI real y ejecutar pruebas Flutter/APK. No se ha compilado ni probado este ZIP.
