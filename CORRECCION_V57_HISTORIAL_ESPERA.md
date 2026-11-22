# V5.7 — historial tras registrar jugadas

**Problema:** tanto la anotación de batazos como las jugadas especiales lanzaban la consulta del historial sin esperar su finalización (`unawaited`). El indicador de jugada en curso podía desaparecer antes de que el historial terminara de actualizarse.

**Corrección:** tras confirmar la RPC, actualizar el marcador y esperar la recarga del historial antes de liberar el control. La cola de `_refreshLiveHistory` se mantiene para absorber solicitudes simultáneas de Realtime.

**Alcance:** mejora la consistencia de la interfaz y la secuencia de refresco. No garantiza por sí sola la recepción de Realtime ni corrige eventuales permisos RLS o fallos de escritura en LAB.

**Verificación:** 11 pruebas Python de contrato superadas; no se ejecutaron pruebas Dart, APK ni SQL. No se modificó Supabase.
