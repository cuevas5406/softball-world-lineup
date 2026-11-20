# Corrección del historial de jugadas · V5.6

El historial se actualizaba solo al terminar un bloque compartido de alineaciones, turnos y pitcheo. Una lectura fallida o un cambio de versión durante ese bloque podía dejar visible la última lista anterior.

La pizarra ahora consulta los 50 eventos confirmados más recientes por ID de partido. Actualiza al entrar, cuando cambia la versión, después de anotar y cada cuatro segundos. Si llega una actualización durante una consulta, vuelve a consultar al terminar. Si falla la lectura de nombres, las jugadas siguen visibles. Si falla la lectura de eventos, se conserva el historial anterior con un aviso.

Para validar en dos teléfonos, anota un boleto, un doble y un out en el mismo partido. Confirma el orden de las tres jugadas en ambos, desconecta un teléfono, registra otra jugada y verifica que la recupere al reconectar o volver a abrir el partido. Si faltan eventos, comprueba si LAB los guardó y si ambos mánagers pueden leerlos. Esta entrega no consultó ni modificó LAB.

Genera la APK de LAB con el workflow **Compilar APK Android - Softball World Lineup** y el secreto `SWL_LAB_PUBLISHABLE_KEY`.

Validación local: 88 pruebas aprobadas y análisis Dart sin errores. Esta entrega contiene el código fuente y no incluye una APK compilada.
