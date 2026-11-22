# Bloque 13 — Mi Equipo: actualización segura de permisos

- Tras salir de Crear equipo, la lista de equipos autorizados se consulta nuevamente en el servidor.
- Si el equipo activo ya no figura en esa lista, se limpian selección, roster y permiso de retiro para no mantener controles activos sobre un equipo revocado.
- Se ignoran respuestas tardías de consultas anteriores mediante versión de solicitud y comprobación de identidad del Future.
- Si queda exactamente un equipo autorizado, se selecciona y se comunica al contenedor padre.
- Se controla igualmente el cambio de lista de equipos autorizados proporcionada por el widget padre.
- Se conservan los formularios y RPC existentes de creación de equipos, registro, fichaje, roster y ajustes.

## Verificación

Pruebas Python de inspección estática; no equivalen a compilar Dart, ejecutar APK o validar RLS en Supabase. Sin cambios en LAB ni producción y sin ejecución de SQL.
