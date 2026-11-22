# V5.7 — Bloque 12: Mi Equipo

- Restaurado acceso visible a **Crear equipo** en la pantalla principal de Mi Equipo, sin reemplazar el RPC seguro `swl_create_team`.
- Después de regresar de Crear equipo se actualiza la lista de equipos autorizados desde el servidor; la creación por sí sola no concede permisos.
- Evita que una respuesta tardía de selección automática cambie el equipo elegido manualmente.
- Conserva registro, fichaje, roster y acceso a ajustes del equipo.

No se modificó Supabase. Validación estática Python solamente; faltan pruebas Dart, compilación Flutter y dos teléfonos.
