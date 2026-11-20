# Verificación previa a APK — V5.6

Fecha: 2026-11-19

## Ejecutado
- ZIP original: comprobación CRC satisfactoria.
- Contratos SQL: `python3 -m unittest discover -s test -p test_v56_proposal_contracts.py` — **7 pruebas aprobadas**.
- Archivo `.github/workflows/build_apk.yml`: inspeccionado. Incluye `flutter pub get --enforce-lockfile`, `flutter analyze`, `flutter test`, pruebas Python y `flutter build apk --release`, con publicación del artefacto.

## No ejecutado
- `flutter analyze`, `flutter test` y `flutter build apk`: Flutter/Dart no instalados en este entorno.
- GitHub Actions: no se lanzó ningún workflow; no hay APK verificada.

## Requisitos para compilar en GitHub
1. Subir el contenido de este ZIP al repositorio, conservando `.github/workflows/build_apk.yml` y `pubspec.lock`.
2. Confirmar que el secreto `SWL_LAB_PUBLISHABLE_KEY` está configurado.
3. Ejecutar **Compilar APK Android - Softball World Lineup** desde Actions o mediante un push a main/master.
4. Si el flujo falla, revisar el primer error de `flutter analyze` o `flutter test` antes de distribuir la APK.

## Base de datos
No se ejecutó SQL ni se modificó Supabase LAB durante esta verificación.
