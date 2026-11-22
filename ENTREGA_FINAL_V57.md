# Softball World Lineup V5.7 — entrega consolidada para compilación

## Incluye
Proyecto Flutter completo con las correcciones acumuladas hasta el bloque 18: alineaciones, borradores, pizarra, sustituciones, Mi Equipo, permisos, Agenda, acceso por PIN e historial sincronizado.

## Validación efectuada en esta entrega
- Suite Python: 59 pruebas estáticas satisfactorias.
- Archivo ZIP comprobado sin errores de integridad.
- Pipeline de GitHub Actions actualizado para ejecutar **todas** las pruebas Python (`test_*.py`), además de `flutter analyze` y `flutter test`, antes de compilar la APK.

## Límites y pendientes obligatorios
- **No** se ha ejecutado `flutter analyze`, `flutter test` ni compilado APK en este entorno: no está instalado el SDK Flutter/Dart.
- **No** se ha probado la sincronización real entre dos teléfonos ni los flujos completos con usuarios de LAB.
- El módulo Agenda/Retos requiere comprobar la presencia de `swl_v56_challenges` y las RPC `swl_v56_send_challenge` y `swl_v56_act_challenge` en Supabase LAB. La última auditoría disponible indicaba que faltaban; por tanto, **Retos no puede declararse operativo**.
- No se ha ejecutado SQL, desplegado código ni modificado Supabase LAB o producción.

## Cómo generar la APK
Subir el contenido de este ZIP a la raíz del repositorio GitHub, configurar el secreto `SWL_LAB_PUBLISHABLE_KEY` y ejecutar el workflow **Compilar APK Android - Softball World Lineup**. El workflow detendrá la compilación si falla análisis, pruebas o falta el secreto. Si termina correctamente, descargar el artifact `Softball-World-Lineup-Instalador`.

## Criterio de cierre real
Una compilación verde y pruebas de dos teléfonos (mismo PIN, ambos mánagers, fan en lectura, alineaciones, anotación, sustituciones, historial y recuperación de conexión), más despliegue autorizado de los contratos de Retos si se desea habilitar esa función.
