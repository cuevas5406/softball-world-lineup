# Bloque 15 — Agenda y Retos

Cambios en lib/main.dart:
- Las solicitudes de refresco recibidas mientras otra consulta está activa se encolan en una bandera y se ejecutan al finalizar la consulta anterior. Esto evita que aceptar, rechazar o preparar un reto muestre una lista obsoleta cuando hay polling concurrente.
- La bandera se reinicia al cambiar de equipo, preservando aislamiento de respuestas.
- El formulario de borrador rechaza fecha/hora pasadas y nombres de rival vacíos o solo espacios.

Sin ejecución SQL, sin modificaciones de Supabase. Pruebas estáticas Python; no hay SDK Flutter disponible para compilar o ejecutar pruebas Dart.
