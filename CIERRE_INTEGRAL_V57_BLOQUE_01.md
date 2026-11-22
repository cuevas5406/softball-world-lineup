# Cierre integral V5.7 — bloque 01

## Cambio realizado
El botón «Actualizar pizarra» ahora espera secuencialmente la lectura del marcador, la alineación y el historial, en lugar de lanzar tres solicitudes paralelas. Esto reduce la posibilidad de presentar un historial de una versión distinta del marcador tras una actualización manual. Se agregaron pruebas estáticas de orden de llamadas.

## Auditoría de integración y riesgos pendientes
- La pizarra de prueba local permite sustituciones por nombre y número, pero **no representa una sustitución transaccional en Supabase**.
- En partidos en vivo, la pizarra delega la sustitución del bateador y el cambio de pitcher a `onLiveSubstitute` y `onLivePitcher`; requieren validación funcional de los callbacks y su persistencia.
- La validación `SwlSubstitutionRequest` exige identidad, roster activo, turno y revisión, pero su existencia por sí sola no demuestra que todas las rutas de UI la apliquen.
- Falta compilar con Flutter/Dart y probar en dos teléfonos, especialmente cambios simultáneos de pitcher y bateador, revisión de alineación, Realtime y reconstrucción del historial.
- Las propuestas SQL de V5.7 no fueron instaladas. No se ejecutó SQL ni se modificó LAB o producción.

## Próximo bloque de cierre
Verificar y corregir el flujo de sustituciones en vivo de extremo a extremo (pantalla → callback → RPC → historial → lectura remota), sin ejecutar migraciones.
