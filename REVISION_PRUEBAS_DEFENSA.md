# Revisión de pruebas de alineación — V5.6

Se actualizaron las pruebas de contratos para exigir defensa completa (9 a 10 asignaciones) en guardado extendido, y se corrigió el caso del editor que antes esperaba guardar solo un pitcher.

El guardado legado sin posiciones conserva validación del orden al bate sin exigir defensa, para evitar regresiones del contrato anterior.

**No se ejecutaron pruebas Flutter:** el SDK Flutter/Dart no está instalado en este entorno. Ejecutar `flutter test` en CI antes de publicar APK.

**Supabase LAB no fue modificado.**
