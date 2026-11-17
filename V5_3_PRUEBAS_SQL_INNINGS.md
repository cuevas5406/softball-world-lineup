# Verificación de carreras por entrada — LAB

Se ejecutaron cinco casos SQL en el proyecto LAB, sin modificar partidos:

1. Visitante anota una carrera en la primera entrada: resultado `[1]`.
2. Local anota dos carreras en la segunda entrada: resultado `[0,2]`.
3. Rechazo de discrepancia entre total y desglose (`INNING_TOTAL_MISMATCH`).
4. Rechazo de carrera atribuida al equipo que no batea (`WRONG_BATTING_TEAM`).
5. Rechazo de entrada futura (`FUTURE_INNING`).

La consulta `DO $$ ... $$` terminó sin excepción. También se verificó que
`swl_v53_record_play` referencia la función interna y que `anon` no tiene
permiso de ejecución. Esto NO prueba una jugada autenticada ni la
sincronización entre dos dispositivos.

Pendiente: pruebas de anotación autenticada, implementación de jugadas
completas con bases y corredores, estadísticas individuales y compilación.
