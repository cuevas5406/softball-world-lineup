# V5.3 — Historial de sustituciones separado

- La consulta del historial de sustituciones ya no depende de las 20 jugadas recientes.
- Se consultan exclusivamente eventos `SUBSTITUTION` del partido activo, ordenados por ID descendente.
- Límite de 500 sustituciones visibles; si existen más, la interfaz lo advierte.
- Se resuelven los nombres de jugadores salientes y entrantes.
- El box score preliminar utiliza el historial separado para identificar sustitutos.
- La consulta se actualiza al conectar el partido, al recibir actualizaciones Realtime, tras una sustitución local o al pulsar el botón de consulta.
- Se invalida el historial al cambiar de partido para impedir mezclar jugadores.

## Limitaciones

La vista no certifica estadísticas oficiales; solo cuenta eventos que el servidor atribuye a un jugador. Si hay más de 500 sustituciones, la identificación histórica puede ser incompleta. No se realizaron pruebas con Flutter SDK ni dos dispositivos.
No se realizaron modificaciones de base de datos en esta entrega.
