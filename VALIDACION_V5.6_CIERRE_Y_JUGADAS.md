# Softball World Lineup V5.6 · Cierre y anotación avanzada

Base del trabajo: proyecto completo de `softball-world-lineup-v5-6-historial.zip`. El caso reportado fue SWL-095994, 10–9 al cerrar la séptima baja. El flujo heredado avanzaba la entrada sin corregir la transición con un resultado final en el servidor. Las propuestas 08 y 09 conservan la anotación heredada, acreditan la jugada y resuelven el estado terminal dentro de la misma transacción antes de que se publique. Se preserva el marcador y la media entrada terminal. El cliente solo bloquea la anotación y anuncia el resultado cuando recibe el estado persistido. El partido histórico no se corrigió retrospectivamente.

## Cambios

| Área | Implementación y alcance |
|---|---|
| Reglamento | Seis entradas por defecto. Empate continúa. Victoria local en la alta completada o al tomar ventaja en su última baja. El visitante debe completar la baja para ganar. En tercera y cuarta se evalúa una diferencia inclusiva de 15 y 10, respectivamente. El visitante espera la oportunidad del local. La propuesta permite cambiar la duración y ajustar o desactivar cada umbral por partido. |
| Cierre por acuerdo | Desde quinta, con ganador en el marcador, ambos mánagers pueden iniciar la solicitud. Solo el otro puede aceptar o rechazar. Por seguridad, una nueva jugada invalida la solicitud anterior. Dos firmas independientes pasan de FINAL a OFFICIAL. Quedan registros de las decisiones en la propuesta 08. |
| Carreras por entrada | Completa con cero las mitades certificadas por el avance del partido, conserva las carreras y deja con guion una baja omitida. El marcador en curso no inventa carreras de una entrada sin datos. |
| Historial | Lee páginas ascendentes por versión e ID, conserva el último historial válido ante un error y descarta eventos repetidos por ID. La consulta sigue siendo independiente de alineaciones y pitcheo. Las bolas y los strikes intermedios actualizan la cuenta de la pizarra y quedan fuera del historial. Las apariciones completadas se muestran como base por bolas o ponche. Las acciones de corredores siguen visibles. El cliente no puede recuperar jugadas que LAB no guardó o que no permita leer. |
| Pitcheo y bateo | La tarjeta muestra IP por outs y K por pitcher cuando existen datos confirmados, incluso cero al inicio. La vista individual distingue datos del partido y temporada. El acumulado de temporada y la reconstrucción de pitcheo histórico requieren una fuente confirmada. Los outs de las nuevas jugadas se acreditan al pitcher. El fly registra SF y RBI en el evento y la ficha individual, sin cargar AB. La vieja agregación del Box Score requiere verificar que incorpore las categorías nuevas. |
| Corredores | Tocar una base ocupada abre permanencia, avance, regreso válido, carrera, out o sustitución. Tocar segunda libre desde sexta ofrece corredor fantasma con «Último out» o jugador elegible. Nunca se coloca automáticamente. El reemplazo de corredor exige identidad conocida y lugar en el orden al bate; el servidor conserva la base y guarda la sustitución. La propuesta sigue la identidad del fantasma durante hits, boletos y acciones manuales. No acredita hit ni turno al colocarlo. La clasificación de carreras limpias exige un contrato adicional de pitcheo. |
| Out especial | OUT normal conserva acceso directo. «Jugadas especiales» aparece si hay corredores y menos de dos outs. El fly valida tercera y permite seleccionar avances legales. El doble play cubre al bateador y un corredor existente, sin carreras simultáneas. El cierre de mitad se evalúa al completar el tercer out. |
| Alineación y Agenda | La edición bloquea aperturas o guardados repetidos mientras se procesa, tolera posiciones persistidas y un pitcher retirado del roster. Conserva pitcher, DH, posiciones y sustituciones. La Agenda existente usa los IDs de ambos equipos y el modelo de retos. Los permisos efectivos de ambos mánagers, equipo externo y aficionados siguen sujetos a la revisión de LAB. |

## Propuestas para revisión

- **08_cierre_transaccional.sql** requiere el contrato verificado de 06, versiones monotónicas y los estados FINAL y OFFICIAL en LAB. La solicitud, la respuesta y cada firma usan un bloqueo de fila, actor autenticado, permisos vigentes y versión esperada. La compatibilidad con funciones V5.3, roles y escrituras directas debe auditarse antes de autorizarlo. Los clientes antiguos que escriban directamente por rutas heredadas no deben saltarse el cierre.
- **09_jugadas_especiales.sql** requiere 06, 07 y 08. Verificar columnas y restricciones de eventos, cursores y forma real de bases. La propuesta admite bases booleanas y un registro separado de identidades; si LAB usa una estructura distinta, la jugada especial se rechaza hasta adaptar el contrato. Las bases de partidos ya empezados pueden carecer de identidad, por lo que un fantasma o una sustitución pueden requerir un partido nuevo. Probar todos los validadores de sustitución, reingreso y permisos, así como los agregados de Box Score.
- **10_diagnostico_partido_solo_lectura.sql** permite distinguir historial oculto de eventos faltantes y comparar el resultado persistido con el caso SWL-095994. Comparar también la lectura bajo los dos mánagers, no solo desde una sesión privilegiada.
- No se ejecutó SQL ni se modificó Supabase LAB o producción. El análisis sintáctico de un archivo no garantiza que coincida con las funciones o datos instalados.

## Validación pendiente en Android

1. Compilar en GitHub Actions con el secreto `SWL_LAB_PUBLISHABLE_KEY`. El artefacto **Softball-World-Lineup-Instalador** contiene `app-release.apk`.
2. Tras revisar y autorizar los cambios necesarios en LAB, usar un PIN nuevo con dos mánagers. Empatar tras seis entradas y ganar 10–9 en la séptima. Confirmar que ambos ven FINAL y que la octava y los controles de anotación quedan bloqueados. Reabrir y comprobar las dos firmas.
3. Probar 15 y 14 de ventaja en tercera, 10 y 9 en cuarta. Con ventaja visitante, dejar batear al local y verificar que el partido continúa si reduce la diferencia.
4. Desde quinta, solicitar, rechazar y solicitar de nuevo, aceptar con el otro usuario y comprobar que el solicitante no puede confirmar. Probar conflicto si se registra una jugada antes de responder.
5. Contrastar ceros inmediatamente al cerrar mitades, bola, strike, out, doble y el historial paginado. Perder señal, reconectar y reabrir en ambos teléfonos.
6. Probar SF, DP, fantasma y sustitución con un partido nuevo. Contrastar AB, H, RBI, SF, IP y K, avances, outs, identidad y recuperación del estado. Verificar que las jugadas normales que funcionaron siguen funcionando y que ambas cuentas ven el reto en Agenda.

Las pruebas automatizadas locales de este ZIP se registran en `evidencias/`. El cierre, la sincronización de jugadas especiales, los cambios de pitcher, las firmas y la reconexión real requieren validación con dos teléfonos.
 
## Resultados locales de esta entrega

- Flutter 3.50.0. `flutter analyze` terminó sin errores, con dos advertencias de utilidades heredadas y avisos informativos.
- `flutter test` aprobó 98 pruebas. Incluye los casos nuevos de resultados, margen de carreras, ceros, solicitudes de mánagers, jugadas especiales e historial.
- APK Release compilada localmente y firma verificada con un valor de prueba para la configuración de LAB. El ZIP contiene las fuentes y el workflow para generar el instalador conectado a LAB.
- Los archivos 08, 09 y 10 pasaron una comprobación sintáctica local de SQL y PL/pgSQL. Las funciones y políticas de LAB requieren revisión y validación independiente.

## Ajuste adicional del historial

El historial de la pizarra y la sección «Jugadas recientes» del Box Score aplican el mismo filtro. El límite del resumen se aplica después de filtrar, para conservar hasta 20 jugadas reales. Se amplió la prueba de la pizarra para verificar bolas y strikes intermedios ocultos, boleto, ponche, doble, out, avance y reconexión simulada. Pasaron 98 pruebas. El análisis terminó sin errores. Las evidencias APK anteriores corresponden a la versión previa a este ajuste. Esta revisión se entrega como código fuente para compilar en GitHub Actions.

## Conteo de lanzamientos por pitcher

Flutter muestra PITCHES, B y S en la ficha del pitcher y en el Box Score. Los datos se agrupan por pitcher y versión confirmada. Las filas antiguas sin datos se marcan como sin conteo o parcial. El historial sigue ocultando bolas, strikes y fouls intermedios.

La revisión de la propuesta 11 acredita B para BALL, S para STRIKE o FOUL y una categoría separada «en juego» para hit, out de bateador, sacrificio y doble play. La cuarta bola y el tercer strike cuentan una vez en su propia anotación. Los avances y outs independientes de los corredores no agregan pitcheos. Para un foul normal, mantén pulsado STRIKE. Con dos strikes, el foul suma al pitcher y deja la cuenta del bateador en dos. La RPC propuesta no aplica una regla especial de toque de foul.

Revisar y autorizar la propuesta 11 antes de probar en LAB, incluida la compatibilidad de FOUL con el catálogo de eventos. Luego verificar en dos teléfonos un cambio de pitcher y que cada uno conserve sus totales. No se ejecutó SQL ni se modificó Supabase. Pasaron 100 pruebas Flutter y el análisis terminó sin errores. La compilación APK documentada anteriormente corresponde a una revisión anterior.

## Revisión de las propuestas SQL

Los cambios posteriores y sus evidencias están en [REVISION_PROPUESTAS_08_09_11.md](REVISION_PROPUESTAS_08_09_11.md).
