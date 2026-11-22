# Cierre integral V5.7 — Bloque 02

## Actualización manual de pizarra
La acción «Actualizar pizarra» fuerza una sola consulta coordinada de alineaciones a través de `_refreshLiveScore(forceLineups: true)`, seguida del historial. Antes ejecutaba `_loadLiveLineups()` otra vez, aunque la consulta de marcador ya podía haberlo hecho. Se conserva el sondeo periódico y la cola de actualizaciones.

## Verificación
Prueba estática de contrato incluida. No se ejecutó Dart/Flutter ni APK ni pruebas de dos teléfonos. No se ejecutó SQL ni se alteró Supabase.
