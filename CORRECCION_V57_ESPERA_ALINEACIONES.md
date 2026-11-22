# V5.7 — Espera de actualizaciones de alineaciones

Cuando dos actualizaciones coincidían, `_loadLiveLineups()` retornaba antes de finalizar la segunda lectura. Ahora las llamadas concurrentes esperan a que termine la lectura pendiente, igual que el marcador y el historial. No se ejecutó SQL ni se modificó Supabase. Validación estática; falta ejecutar Flutter/Dart y probar en dos teléfonos.
