# Bloque 11 — Sustituciones y respuesta incierta

- Corregida la clasificación de errores de RPC de sustitución: un código ausente ya no se considera rechazo explícito.
- Códigos HTTP 5xx, SQLSTATE de conexión y errores internos dejan el estado como incierto para impedir reintentos potencialmente duplicados.
- El mensaje de fallo pide actualizar y revisar la alineación antes de repetir.
- Añadida prueba Dart de clasificación (preparada, no ejecutada: no hay SDK Flutter en este entorno).
- No se ejecutó SQL ni se modificó Supabase. Mi Equipo queda para el próximo bloque acordado.
