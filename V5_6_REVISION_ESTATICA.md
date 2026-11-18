# V5.6 — revisión estática de batazos

- El formulario de batazos reside en `swl_advanced_scoreboard.dart`, no en la confirmación del PIN.
- Se valida la versión del partido antes de abrir el formulario; el RPC vuelve a validar la versión al registrar.
- El avance sugerido para sencillo/doble/triple/jonrón se calcula desde las bases realmente ocupadas. El mánager puede ajustar destinos; se impiden destinos duplicados.
- Se valida la presencia de `team_id` para evitar consultas con el texto `null`.
- Sin cambios en Supabase ni en producción.
- No se ejecutó compilación Flutter ni prueba en dos teléfonos; deben realizarse mediante GitHub Actions y dispositivos.
