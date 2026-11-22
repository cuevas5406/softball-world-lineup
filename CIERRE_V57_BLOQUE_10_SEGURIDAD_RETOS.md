# V5.7 — Bloque 10: endurecimiento de propuesta Retos

- **No ejecutado en LAB**: solo edición de archivos locales.
- Agregadas restricciones de integridad para nombre del rival externo (sin espacios periféricos, 1–100 caracteres) y longitud del estadio (máximo 150).
- Validación explícita de equipo local no nulo antes de enviar reto.
- Preflight ampliado para inspeccionar propietario, SECURITY DEFINER, search_path y permisos EXECUTE de `anon` y `authenticated`.
- **Advertencia**: la migración aún requiere revisión transaccional y autorización expresa; no se confirma compatibilidad funcional ni seguridad integral sin ejecutar diagnóstico y pruebas de permisos en LAB.
- **Pendiente**: Mi Equipo, compilación Flutter, pruebas en dos teléfonos.
