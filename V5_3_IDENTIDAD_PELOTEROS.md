# V5.3 — Identidad de peloteros (fase preparatoria)

- Se añadió `playerId` opcional al modelo local `SwlScorePlayer`, preservado por `copy()`.
- Editar nombre o número invalida el vínculo anterior para no atribuir estadísticas a un jugador distinto.
- `SwlLineupIdentity` valida alineaciones de 9–13, IDs únicos, posiciones, DH/AH y genera un payload ordenado para futura persistencia.
- `payload(requireIds: true)` rechaza jugadores locales sin ID real. El usuario no pierde la posibilidad de jugar localmente.
- Se añadieron seis pruebas unitarias (escritas, NO ejecutadas).
- PENDIENTE: enlazar selección de roster real, persistencia y autorización por equipo en LAB, RPC de jugadas con IDs, estadísticas por jugador, sincronización entre dispositivos y pruebas Flutter.
- No se modificó Supabase LAB ni producción durante este bloque.
