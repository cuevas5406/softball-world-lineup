# Alineaciones persistentes en LAB (V5.3)

Se creó `public.swl_game_lineups` con clave `(game_id, team_id)`, orden de bateo JSONB, revisión, mánager y fecha. RLS habilitado; lectura para mánagers participantes; escritura directa denegada.

La RPC `swl_v53_save_lineup(uuid,uuid,uuid[])` bloquea el partido, exige sesión, mánager de ese equipo con autorización vigente, 9 a 13 UUID únicos y pertenencia a rosters activos. Solo después guarda la alineación.

Flutter envía el orden seleccionado a la RPC. No hay aún edición defensiva/DH/AH en este formulario, bloqueo de alineación al comenzar partido, ni atribución de jugadas a jugadores. La tabla y RPC ya están instaladas en LAB, no producción.

Pruebas SQL realizadas: permisos anon=false, authenticated=true; RLS=true; llamada sin auth rechazada. No se ejecutaron pruebas con mánagers autenticados ni Flutter SDK.
