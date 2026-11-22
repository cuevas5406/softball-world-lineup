# Bloque 18 — historial en dos teléfonos

- Suscripción INSERT de `swl_game_events` filtrada por `game_id`.
- Al llegar un evento, recarga historial desde SELECT, no confía en el payload.
- Cola de actualización si hay consulta en curso, para no perder el último evento.
- Consulta de respaldo cada 12 segundos si falla Realtime.
- Al cambiar de partido, invalida solicitudes previas y limpia la cola.

Sin cambios en Supabase. Pruebas Flutter y en dos teléfonos pendientes.
