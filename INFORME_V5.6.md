# Softball World Lineup V5.6

## Alcance

Candidato para validar contra Supabase LAB. Se trabajó sobre `softball-world-lineup-v5-6-validacion-estado-partido(2).zip`. Se preservó la distribución de la pizarra original en `lib/swl_advanced_scoreboard.dart`, con el marcador por entrada, conteo, diamante, tarjetas de jugadores, controles e historial en sus posiciones originales. La confirmación del PIN muestra los equipos y el acceso correspondiente. La anotación en vivo se realiza en la pizarra oficial.

## Correcciones

| Área | Cambio |
|---|---|
| Código Flutter | Se corrigió un cierre de paréntesis que impedía analizar y compilar la pizarra del ZIP de partida. |
| PIN y espectadores | El invitado puede abrir «Ver partido por PIN» desde la bienvenida. Consulta por PIN con una lectura del partido y abre la pizarra oficial con los controles deshabilitados. La RPC de enlace queda reservada al flujo del visitante con sesión y equipo autorizado. |
| Turno de anotación | La pizarra habilita las acciones en `IN_PROGRESS` para el mánager del lado que batea. El lobby revalida sesión, equipo y versión antes de enviar. Se envía la versión que estaba en pantalla al elegir la jugada, incluida la confirmación de batazos y cambios de mitad. |
| RPC de anotación | `swl_v53_record_plate_action` recibe el bateador del turno vigente para bola, strike y out. `swl_v53_apply_hit_for_player` recibe los destinos explícitos de los corredores. La vista previa y el envío usan el mismo motor de avance. Ante un rechazo explícito se muestra el mensaje y ante una respuesta incierta se consulta la siguiente versión en el historial. |
| Sincronización | La suscripción Realtime se filtra por ID de partido. La pizarra recibe las actualizaciones a través del lobby y conserva la consulta periódica de respaldo. Se descartan lecturas con versión inferior y se consultan las alineaciones, turnos e historial por partido. |
| Alineaciones y estadísticas | Se muestran el bateador vigente y sus números cuando están sincronizados y hasta 50 eventos recientes en el historial de la pizarra. Las estadísticas preliminares leen los eventos paginados por partido. La preparación conserva acceso a roster, sustitución, estadísticas e historial. |
| Equipos y agenda | Los equipos autorizados se leen en páginas de 100 y se comprueban en lotes de ocho en paralelo. Se mantuvieron los flujos de registro y fichaje. La agenda conserva borradores de retos con fecha, hora y estadio elegidos. «Preparar partido en vivo» abre el lobby con la búsqueda del rival y permite confirmar un equipo real. El servidor asigna el PIN al crear el partido. Los borradores de agenda viven en la sesión de la aplicación. |
| Android y CI | El ZIP incluye el proyecto Android, el logo existente en densidades Android, permisos de Internet, consulta WhatsApp, el retorno `com.softballworld.lineup://login-callback` y las dependencias fijadas en `pubspec.lock`. GitHub Actions analiza, prueba y genera la APK de LAB. |

## Resultados verificados

Las comprobaciones locales se ejecutaron el 18 de noviembre de 2026 con Flutter 3.50.0 y Dart 3.14.0. Los registros están en `evidencias/`.

| Comprobación | Resultado |
|---|---|
| Dependencias con lockfile | Resueltas con `dart pub get --offline --enforce-lockfile`. |
| Análisis Flutter de `lib` y `test` | 0 errores. Quedan 2 avisos por métodos privados sin referencias y 15 avisos informativos por APIs deprecadas. |
| Pruebas Flutter | 79 aprobadas. Incluyen turnos de mánager, estados cerrados, avances inválidos y una prueba de la pizarra de solo lectura que mantiene la última versión del marcador. |
| Compilación Flutter para Android ARM64 | Se generó `app.so` de Release y se confirmó que es un binario AArch64. Se usó un valor de prueba para compilar, sin conexión a LAB. |
| APK Android Release | Gradle generó y firmó `app-release.apk` (55.461.974 bytes). Se verificaron la firma y las tres variantes nativas. La compilación local usó un valor de prueba. La APK utilizable contra LAB se genera con la clave publicable mediante el workflow. |
| Manifiesto y workflow | Manifiesto Android y YAML verificados. Se comprobó el filtro de retorno de autenticación y la ruta del instalador en Actions. |

## Obtener la APK de LAB

1. Extrae el ZIP y sube su contenido a la raíz de tu repositorio GitHub. Incluye `.github/workflows/build_apk.yml`, `android/` y `pubspec.lock`.
2. En GitHub abre **Settings → Secrets and variables → Actions** y agrega el secreto `SWL_LAB_PUBLISHABLE_KEY` con la clave publicable del proyecto LAB. La URL de LAB está configurada en el workflow. Usa la clave publicable y conserva las claves de servicio fuera de la APK y del repositorio.
3. En **Actions**, ejecuta **Compilar APK Android - Softball World Lineup** con **Run workflow**. Si el trabajo termina correctamente, abre su sección **Artifacts** y descarga **Softball-World-Lineup-Instalador**. Dentro encontrarás `app-release.apk`.
4. Instala la APK en los teléfonos de prueba. El proyecto usa firma de depuración para la Release de LAB. Android puede exigir desinstalar una APK con el mismo identificador que se haya firmado con otra clave.

También se puede compilar en un equipo con Flutter 3.50.0, JDK 21, Android SDK y la clave publicable LAB cargada en la variable `SWL_LAB_PUBLISHABLE_KEY`.

```bash
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-infos --no-fatal-warnings lib test
flutter test
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://wgeziptdoabyicufnrfk.supabase.co \
  --dart-define=SUPABASE_ANON_KEY="$SWL_LAB_PUBLISHABLE_KEY"
```

La salida esperada de Gradle es `build/app/outputs/flutter-apk/app-release.apk`.

## Validación de integración pendiente en LAB

| Escenario | Resultado esperado |
|---|---|
| Dos mánagers con equipos y rosters distintos | El local crea un partido; el visitante introduce el PIN de seis dígitos y confirma su equipo. Cada mánager guarda su alineación, abre la pizarra oficial y puede anotar en su mitad cuando el partido está en curso. |
| Tercer out y actualización | Registra dos outs y un tercero desde la pizarra. Ambos teléfonos deben reflejar el cambio de mitad, las bases limpias y el traspaso de permisos de anotación. |
| Batazo y concurrencia | Prueba sencillo, doble, triple y jonrón con corredores. Si cambia la versión mientras el modal está abierto, la confirmación debe pedir revisar el marcador. Tras perder conexión, vuelve a abrir el partido y contrasta marcador e historial antes de repetir una jugada. |
| Aficionado | Consulta el mismo PIN como invitado y como usuario sin asignación de mánager. Verifica que puede leer el resultado y que todos los botones de anotación permanecen deshabilitados. Requiere permisos de lectura en LAB para el rol correspondiente. |
| Aislamiento y escala | Prueba dos PIN de partidos abiertos simultáneamente y un catálogo de más de 100 equipos. Verifica que cada pizarra solo cambia con su propio partido y que una búsqueda encuentra equipos de páginas posteriores. Mide latencia con los datos reales de LAB. |
| Contrato de servidor | Verifica la transición a `IN_PROGRESS`, la publicación Realtime, las políticas de lectura y los permisos efectivos de cada RPC. El cliente presupone que las RPC aplican los permisos y la versión esperada en la misma transacción. |

Durante este trabajo no se ejecutó SQL ni se modificó Supabase LAB o producción. Las notas históricas del ZIP se conservaron para referencia. Las jugadas defensivas avanzadas del modo local, la firma oficial del resultado y las estadísticas de lanzador siguen sujetas al contrato efectivo del servidor. La pizarra muestra valores de pitcheo pendientes en vivo mientras ese dato no está disponible.
