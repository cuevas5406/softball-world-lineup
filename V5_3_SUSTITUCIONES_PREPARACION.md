# Sustituciones — preparación segura, no activadas

Se incorpora `SwlSubstitutionRequest` con validación pura y cinco pruebas unitarias.
Esta versión NO permite sustituir durante un partido ni modifica el backend.

Para activar sustituciones falta una RPC que en una sola transacción:
1. Verifique mánager, partido abierto, equipo, roster y revisión.
2. Bloquee el partido, alineación y turno; compruebe el jugador saliente.
3. Registre jugador entrante y saliente, orden al bate, instante y autor en un historial inmutable.
4. Mantenga el mismo número de orden al bate y preserve estadísticas históricas por player_id.
5. Actualice la alineación vigente y su revisión; valide la siguiente jugada contra ella.
6. Defina explícitamente reglas de reingreso y cambios de lanzador/defensa.

No se han ejecutado pruebas Flutter ni de dispositivos. Producción no se modifica.
