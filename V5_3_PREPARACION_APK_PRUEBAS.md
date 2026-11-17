# V5.3 — Puerta de calidad para APK de pruebas

## Integración GitHub Actions

Después de `flutter pub get` y antes de `flutter build apk --release`, el workflow ahora:

1. Ejecuta `dart analyze` sobre cuatro módulos puros de reglas.
2. Ejecuta cinco archivos de pruebas Flutter: sustituciones, identidad de alineaciones, jugadas, totales por entrada y repositorio de roster.
3. Solo inicia la compilación APK si todas las verificaciones anteriores terminan correctamente.

Se añadieron tres pruebas a sustituciones: turno inexistente, jugador entrante idéntico al saliente y revisión inválida.

## Limitaciones

No se ejecutó Flutter en este entorno porque no hay SDK instalado. La ejecución de GitHub Actions está pendiente. Estos tests comprueban reglas locales; **no sustituyen** las pruebas con dos dispositivos, permisos reales de LAB y concurrencia de RPC.

No se modificó Supabase ni producción.
