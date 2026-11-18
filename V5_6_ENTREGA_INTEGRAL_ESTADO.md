# Softball World Lineup V5.6 — estado verificable

## Cambios de esta entrega
- Se añadió prueba de permisos de anotación por mitad de entrada, estado de partido y espectadores.
- La pizarra solo habilita anotación para partidos IN_PROGRESS; el servidor sigue siendo la autoridad.
- Se muestran los errores concretos de registro en vez de ocultarlos bajo un mensaje genérico.
- GitHub Actions ejecutará análisis de Flutter y pruebas antes de compilar el APK.
- Se preservaron el diseño original y el selector de batazos dentro de la pizarra.

## Límites de validación
- El entorno local no dispone de Flutter ni Dart; no se ha ejecutado `flutter analyze`, `flutter test` ni `flutter build apk`.
- El flujo de dos teléfonos, la consistencia de RPC y la carga de 100+ partidos necesitan pruebas reales.
- No se modificó ninguna base de datos ni se ejecutó SQL.
- El ZIP es candidato de compilación, NO una APK verificada.

## Para compilar
1. Subir el proyecto a GitHub manteniendo `.github/workflows/build_apk.yml`.
2. Configurar el secreto `SWL_LAB_PUBLISHABLE_KEY` con la clave publicable de LAB.
3. Ejecutar manualmente el workflow `Compilar APK Android - Softball World Lineup`.
4. Revisar los pasos de análisis y pruebas; si fallan, compartir el log para corregirlo.
5. Solo después de compilación satisfactoria probar en dos dispositivos con dos mánagers.
