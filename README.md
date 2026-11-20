# Softball World Lineup V5.7

El [informe de entrega](INFORME_V5.7.md) incluye la matriz de cumplimiento, los archivos modificados y las verificaciones pendientes en LAB y Android.

## APK mediante GitHub Actions

Extrae este ZIP en la raíz del repositorio. Conserva `.github/workflows/build_apk.yml` y configura el secreto de repositorio `SWL_LAB_PUBLISHABLE_KEY`. Ejecuta **Compilar APK Android - Softball World Lineup** en **Actions**. Si finaliza correctamente, el artefacto **Softball-World-Lineup-Instalador** contendrá `app-release.apk`.

## Entrega anterior V5.6

## Compilar la APK con GitHub Actions

1. Extrae este ZIP en la raíz del repositorio. Deben quedar allí `pubspec.yaml`, `android/` y `.github/workflows/build_apk.yml`.
2. Configura el secreto de repositorio `SWL_LAB_PUBLISHABLE_KEY` con la clave publicable de LAB.
3. En **Actions**, ejecuta **Compilar APK Android - Softball World Lineup**. Descarga **Softball-World-Lineup-Instalador**, que contiene `app-release.apk`.

## Correcciones de esta entrega

- Los mánagers pueden abrir la preparación desde un partido guardado. El botón de inicio se habilita al mánager local cuando ambos lados tienen mánagers distintos y un orden confirmado de 9 a 13 bateadores.
- El editor mueve cada bateador con flechas y admite los turnos 12 y 13. Al usar un pitcher que solo defiende, el DH debe estar en el orden al bate y fuera de la defensa. Las posiciones del perfil, principal y secundaria, se muestran en el roster y el editor. El mánager puede asignar otra posición de juego.
- Cada edición actualiza un borrador en el teléfono, identificado por cuenta, partido, equipo y revisión. **Continuar después** conserva el borrador. **Cancelar** restaura el borrador previo o descarta los cambios si era la primera edición. **Guardar alineación** solicita la confirmación al servidor.
- El cliente reconsulta el marcador y la alineación si cambian mientras hay otra lectura en curso. Una sustitución o cambio de pitcher con respuesta incierta se puede verificar desde la preparación antes de reintentar.

## Verificación

- Flutter 3.50.0 y Dart 3.14.0 resolvieron las dependencias con el lockfile.
- Pasaron 122 pruebas Flutter y 7 comprobaciones estáticas de los contratos SQL. El análisis Flutter informó 0 errores, 2 advertencias heredadas y 18 avisos informativos.
- La compilación local se detuvo por ausencia del Android SDK. El workflow está incluido. Quedan por verificar la ejecución en GitHub Actions y el flujo con dos teléfonos usando un partido de prueba distinto de **SWL-929159**.
- La integración en vivo depende de las RPC instaladas en LAB, incluido el soporte de 13 turnos en las funciones que utiliza el cliente. Los archivos de `propuestas_lab/` son los borradores existentes. Durante esta entrega no se accedió a Supabase, no se ejecutó SQL y no se modificó **SWL-929159**.

## Referencias de entregas anteriores

Plataforma oficial de sóftbol en República Dominicana e internacional: anotación en vivo jugada a jugada, estadísticas MLB, rankings nacionales virales, carnet digital por ID, gestión de dobles juegos y modo offline para estadios sin internet.

La entrega V5.6, las pruebas y las instrucciones de compilación de la APK se encuentran en [INFORME_V5.6.md](INFORME_V5.6.md).

## Corrección posterior a las pruebas Android

Consulta [VALIDACION_V5.6_POST_PRUEBAS.md](VALIDACION_V5.6_POST_PRUEBAS.md) para conocer las correcciones de esta entrega, sus resultados y las propuestas de LAB pendientes de autorización.

## V5.6 · Cierre y jugadas avanzadas

Consulta [VALIDACION_V5.6_CIERRE_Y_JUGADAS.md](VALIDACION_V5.6_CIERRE_Y_JUGADAS.md) para revisar el reglamento, la compilación y las pruebas pendientes en LAB y en dos teléfonos.
