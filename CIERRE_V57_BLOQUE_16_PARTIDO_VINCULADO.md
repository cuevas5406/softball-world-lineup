# Bloque 16 — Preparación y apertura del partido vinculado

- `lib/main.dart`: PREPARE/OPEN comprueban la existencia de `game_id` y de un PIN no vacío antes de abrir el partido.
- Si PREPARE devolvió un `game_id` pero falla la lectura del PIN, se explica que el partido ya se preparó y se actualiza Agenda para que el mánager use **ABRIR PARTIDO** en vez de duplicar la operación.
- Si la operación RPC devuelve error o timeout, se vuelve a consultar Agenda porque el servidor podría haber confirmado el cambio aunque la respuesta se perdiera.
- Se conserva el aislamiento por equipo y el bloqueo de acciones simultáneas.
- Sin SQL ejecutado, sin cambios en Supabase. La compilación Flutter y las pruebas entre dos teléfonos siguen pendientes.
