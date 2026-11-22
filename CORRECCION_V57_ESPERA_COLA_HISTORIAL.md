# V5.7 — espera real de la cola del historial

La entrega anterior esperaba `await _refreshLiveHistory()`, pero si Realtime ya estaba cargando el historial, el método solo marcaba `_historyQueued` y retornaba inmediatamente. Esto permitía habilitar otra anotación antes de completar la recarga solicitada.

Ahora las solicitudes simultáneas esperan un `Completer` compartido, que se completa cuando la consulta en curso y la consulta pendiente terminan. La lógica de reintento y manejo de errores se conserva.

**Validación:** pruebas estáticas Python; Dart/Flutter no ejecutado. SQL no instalado. Producción y LAB sin cambios.
