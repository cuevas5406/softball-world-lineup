# Softball World Lineup V5.6 — Alineaciones

La entrega parte de `softball-world-lineup-v5-6-alineacion-simple-parcial.zip`. Conserva la pizarra oficial `swl_advanced_scoreboard.dart` y las propuestas 08, 09 y 11 del paquete de revisión. Los cambios de backend están en archivos de propuesta. Durante este trabajo se ejecutaron pruebas locales y análisis de sintaxis, sin conectar a Supabase ni ejecutar SQL.

## Cambios en el proyecto

| Archivo | Cambio |
| --- | --- |
| `lib/main.dart` | Registro con posición principal y secundaria. Edición desde la ficha del roster para mánagers autorizados. El registro sin secundaria sigue usando la RPC original. Se conserva el flujo existente de fichaje y recuperación del ID. |
| `lib/swl_player_positions.dart` | Etiqueta de ambas posiciones y validación de una secundaria distinta y reconocida. La posición principal histórica conserva su formato. |
| `lib/swl_roster_repository.dart` | Carga de la posición secundaria con compatibilidad cuando la columna todavía no está disponible. |
| `lib/swl_live_lobby.dart` | Recupera la alineación guardada, normaliza el rol P usando el UUID del pitcher, envía la revisión esperada y da mensajes específicos para RPC ausente, defensa rechazada o revisión obsoleta. |
| `lib/swl_lineup_editor.dart` | Mantiene el diálogo deportivo con un solo flujo. Incluye flechas de orden, posiciones táctiles, ocupantes, pitcher y BD. |
| `lib/swl_lineup_draft.dart` | Calcula el orden y el mapa defensivo desde la misma selección. Si el pitcher batea, su UUID aparece una vez en el orden. Con BD queda en defensa y el BD ocupa un turno sin posición defensiva. Mantiene la edición histórica de solo orden al bate. |
| `propuestas_lab/01_inicio_y_alineacion.sql` | Contrato extendido con validaciones específicas para orden, roster, P, BD y posiciones ocupadas. Delega persistencia, bloqueo y revisión a `swl_v53_save_lineup_checked` dentro de la misma operación. |
| `propuestas_lab/05_cambio_pitcher.sql` | Cuando ambos pitchers batean, el saliente toma la posición defensiva que dejó el entrante, si tenía una. El historial de cambios conserva los UUID y registra la versión. |
| `propuestas_lab/12_posiciones_del_pelotero.sql` | Columna nullable y RPC separadas para registro con secundaria y edición autorizada. Conserva los códigos SWL y reutiliza el generador instalado. |
| `test/swl_lineup_draft_test.dart`, `test/swl_lineup_editor_test.dart`, `test/test_v56_proposal_contracts.py` | Cobertura de carga útil, regla de BD, asignación sin depender del perfil, cambios defensivos, controles táctiles, validación y contratos SQL por inspección. |

El rechazo observado `INVALID_PITCHER_OR_POSITIONS` puede producirse si el UUID del pitcher, la casilla P y su presencia al bate discrepan. El editor anterior trataba esos datos como valores separados. Esta versión deriva el pitcher de P y construye la carga útil con esas mismas reglas. El cuerpo exacto de la RPC instalada en LAB y el motivo de su rechazo todavía requieren comprobación autorizada. La prueba automatizada de guardado cubre la solicitud construida en Flutter.

Al elegir un nuevo pitcher antes del encuentro, se intercambia la posición que deja libre cuando ya jugaba a la defensa. Las posiciones del perfil sirven como referencia visual. Las estadísticas de pitcheo conservan los UUID de cada lanzamiento y el cambio de posición no reescribe los eventos de pitcheo. Este comportamiento se revisó estáticamente para las propuestas y debe verificarse en el partido real.

## Pruebas ejecutadas

| Comprobación | Resultado |
| --- | --- |
| `flutter pub get --offline --enforce-lockfile` | Dependencias resueltas con el archivo de bloqueo. |
| `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings lib test` | 0 errores. 2 avisos existentes de métodos sin referencias y 18 notas informativas de API deprecada, incluidas las importaciones Material del nuevo diálogo y su prueba. |
| `flutter test --no-pub --reporter expanded` | 113 pruebas pasaron. Se incluyen 8 pruebas de alineación y posiciones y una prueba de interfaz sobre el diálogo real. |
| `python3 -m unittest discover -s test -p test_v56_proposal_contracts.py -v` | 7 pruebas estáticas pasaron. Incluyen regresiones de 08, 09 y 11 y comprobaciones de las propuestas 01, 05 y 12. |
| `pglast` | Análisis de sintaxis SQL y PL/pgSQL sobre las 13 propuestas, sin ejecutar sentencias. |
| Comparación con la revisión anterior | Pizarra oficial y propuestas 08, 09 y 11 idénticas byte a byte. |

Los registros de esta entrega se encuentran en `evidencias/alineaciones-v56-*`. Quedan pendientes la compilación Android, la prueba del guardado en LAB y la prueba en dos teléfonos.

## Verificación previa a una aplicación autorizada en LAB

1. Confirmar firma, tipos y retorno reales de `swl_register_player`, incluidos el tipo de `p_jersey_number` y los nombres de ID/código. La propuesta 12 parte de argumentos de texto y una fila de retorno con UUID. Verificar asimismo que el tipo de `players.primary_position` y las reglas vigentes de lectura y propiedad del perfil coincidan con el cambio. La edición propuesta requiere un fichaje regular activo y exclusivo. Un fichaje como refuerzo no concede edición global del perfil.
2. Comparar `swl_v56_save_lineup` y `swl_v53_save_lineup_checked` con la propuesta 01, especialmente las revisiones, bloqueos tras la primera acción y el conjunto admitido de jugadores. Si la tabla o el historial de la propuesta 05 ya existen, revisar solo el reemplazo de la función en lugar de reaplicar sus objetos iniciales.
3. Verificar en LAB autorizado el registro con y sin secundaria, incluida su eliminación desde la ficha y un caso de mánager rival sin permisos. La propuesta 12 conserva el flujo separado de registro y fichaje que usa la app. La propuesta 04 del generador SWL permanece pendiente de confirmar contra la implementación instalada.
4. En el teléfono local, guardar un pitcher que batea y luego una alineación con BD. Comprobar que sube una sola revisión por guardado, que el teléfono rival ve la alineación confirmada y que ambos muestran el mismo pitcher. Abrir una alineación antigua sin pitcher y verificar el guardado de solo orden.
5. Con el juego en vivo, registrar lanzamientos con el primer pitcher, cambiarlo entre bateadores y registrar lanzamientos con el segundo. Comparar PITCHES, B, S y lanzamientos en juego por UUID en ambos teléfonos, incluida una reconexión. Confirmar corredores, cambio de ofensiva y cierres según las reglas de las propuestas 08, 09 y 11.

## APK mediante GitHub Actions

Sube el contenido de la carpeta del proyecto a la raíz del repositorio, incluida `.github/workflows/build_apk.yml`. Configura el secreto de repositorio `SWL_LAB_PUBLISHABLE_KEY` con la clave publicable de LAB. En **Actions**, ejecuta **Compilar APK Android - Softball World Lineup**. Cuando el flujo finalice correctamente, descarga el artefacto **Softball-World-Lineup-Instalador**, que contiene `app-release.apk`. El flujo de compilación y la configuración de LAB se conservaron.
