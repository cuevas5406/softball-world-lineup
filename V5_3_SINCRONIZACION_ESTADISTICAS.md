# V5.3 — Sincronización de estadísticas individuales

- Actualiza estadísticas tras eventos Realtime y en la consulta periódica de 3 segundos.
- Evita que respuestas de un partido anterior sobrescriban el partido actual.
- Si hay una solicitud en curso, una segunda solicitud queda en cola para refrescar después.
- Muestra errores de consulta separados del estado de anotación, y estado vacío.
- Tras reconciliar una anotación de resultado incierto también actualiza estadísticas.
- Elimina una condición redundante de los botones de anotación.

**Límites:** no se han probado las llamadas con dos mánagers autenticados;
no se ha compilado Flutter en este entorno. Sin cambios de base de datos.
