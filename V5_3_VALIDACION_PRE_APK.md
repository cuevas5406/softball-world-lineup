# V5.3 — Validación antes de la APK

- Se incorporó la validación pura `SwlSubstitutionRequest` al formulario real de sustituciones.
- El servidor LAB conserva la validación definitiva y el control de concurrencia.
- GitHub Actions ahora analiza **todos** los archivos `lib/` y `test/`, no solo cuatro módulos.
- GitHub Actions ejecuta **todas** las pruebas Flutter detectadas, no una lista fija.
- Los avisos y sugerencias del analizador no bloquean el flujo; los errores sí.
- La compilación release y la protección de conexión exclusiva a LAB se conservan.

## Verificación pendiente

No se ejecutó Flutter ni GitHub Actions en este entorno. La compilación real y las pruebas de teléfono/tablet deben verificarse mediante el workflow. No se modificó ninguna base de datos.
