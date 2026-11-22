# V5.7 — Bloque 09: preinstalación segura de Agenda y Retos

Se añadió `propuestas_lab/00_preflight_agenda_retos_v57.sql`, un diagnóstico exclusivamente SELECT, sin cambios a la base de datos. El objetivo es comprobar dependencias, firmas de funciones, políticas RLS y columnas antes de autorizar `02_retos.sql`.

Verificación read-only ya realizada mediante conexión a LAB: existen `swl_can_manage_roster(uuid)` y `swl_v5_create_game(uuid,uuid)`, ambas SECURITY DEFINER. No se encontraron las funciones `swl_v56_send_challenge` y `swl_v56_act_challenge`. La tabla de retos tampoco aparecía en la enumeración de tablas.

**Pendiente**: revisión de permisos de ejecución de funciones, esquema real, flujo de creación de partido y validación con dos teléfonos. No se aplicaron migraciones. No se cambió la pantalla Mi Equipo en este bloque: su comportamiento definitivo debe decidirse y probarse sin eliminar el acceso a crear equipos por accidente.

Pruebas Python y Dart no equivalen a compilación Flutter ni a integración real con Supabase.
