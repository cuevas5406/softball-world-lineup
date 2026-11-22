# Bloque 03 — sustituciones seguras

- La pantalla de sustitución local no abre un selector vacío si el equipo carece de alineación.
- El índice de turno se ajusta si quedó fuera del rango de la alineación actual.
- La edición local no se aplica a partidas en vivo: allí se utiliza el callback de sustitución persistente.
- La validación de solicitudes rechaza identificadores compuestos solo por espacios.
- Se añaden dos pruebas Dart de regresión (no ejecutadas: Flutter SDK no disponible en este entorno).
- No se ejecutó SQL ni se modificó Supabase.
- Pendiente: verificar sustituciones reales, cambios de pitcher y sincronización en dos dispositivos.
